//! Drives Codex through `codex app-server`: newline-delimited JSON-RPC over stdio
//! (no "jsonrpc" field). One app-server process and one thread per run of Sidefolk.
//! Command and file-change approvals are routed to the pet.

use std::{
    collections::HashMap,
    path::PathBuf,
    process::Stdio,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicI64, Ordering},
    },
};

use serde_json::{Value, json};
use tauri::{AppHandle, Emitter};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    process::{Child, ChildStdin, Command},
    sync::oneshot,
};

use crate::bus::{self, AgentEvent, Decision, PermissionAsk, Shared, clip};

type Reply = Result<Value, String>;

pub struct Codex {
    stdin: tokio::sync::Mutex<ChildStdin>,
    next_id: AtomicI64,
    waiting: Mutex<HashMap<i64, oneshot::Sender<Reply>>>,
    thread_id: tokio::sync::Mutex<Option<String>>,
    alive: AtomicBool,
    busy: AtomicBool,
    cwd: PathBuf,
    /// Paths touched by each fileChange item, for the approval bubble.
    changes: Mutex<HashMap<String, String>>,
    last_message: Mutex<String>,
    _child: Mutex<Child>,
}

pub async fn dispatch(app: &AppHandle, shared: Arc<Shared>, prompt: String) -> Result<String, String> {
    let codex = {
        let mut slot = shared.codex.lock().await;
        match slot.as_ref() {
            Some(codex) if codex.alive.load(Ordering::SeqCst) => codex.clone(),
            _ => {
                let codex = Codex::start(app.clone(), shared.clone()).await?;
                *slot = Some(codex.clone());
                codex
            }
        }
    };
    if codex.busy.swap(true, Ordering::SeqCst) {
        return Err("Codex is still working on the last request.".into());
    }
    let result = async {
        let thread = codex.thread().await?;
        codex
            .request(
                "turn/start",
                json!({
                    "threadId": thread,
                    "input": [{ "type": "text", "text": prompt, "text_elements": [] }],
                    "effort": "low"
                }),
            )
            .await?;
        Ok(thread)
    }
    .await;
    if result.is_err() {
        codex.busy.store(false, Ordering::SeqCst);
    }
    result
}

/// Where dispatched work runs until project selection exists: a scratch folder that
/// SIDEFOLK_WORKDIR can override.
fn workdir(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = match std::env::var_os("SIDEFOLK_WORKDIR") {
        Some(dir) => PathBuf::from(dir),
        None => crate::settings::data_dir(app)
            .map_err(|e| e.to_string())?
            .join("playground"),
    };
    std::fs::create_dir_all(&dir).map_err(|e| format!("Cannot create {}: {e}", dir.display()))?;
    Ok(dir)
}

/// GUI apps on macOS start with a minimal PATH; agent CLIs live in the usual user locations.
pub fn agent_path() -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    let mut parts: Vec<String> = std::env::var("PATH")
        .unwrap_or_default()
        .split(':')
        .filter(|p| !p.is_empty())
        .map(String::from)
        .collect();
    for extra in ["/usr/local/bin", "/opt/homebrew/bin", &format!("{home}/.local/bin")] {
        if !parts.iter().any(|p| p == extra) {
            parts.push(extra.to_string());
        }
    }
    parts.join(":")
}

impl Codex {
    async fn start(app: AppHandle, shared: Arc<Shared>) -> Result<Arc<Self>, String> {
        let cwd = workdir(&app)?;
        let mut child = Command::new("codex")
            .arg("app-server")
            .current_dir(&cwd)
            .env("PATH", agent_path())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .map_err(|e| format!("Could not start Codex ({e}). Is the Codex CLI installed?"))?;
        let stdin = child.stdin.take().ok_or("Codex has no stdin")?;
        let stdout = child.stdout.take().ok_or("Codex has no stdout")?;
        let codex = Arc::new(Self {
            stdin: tokio::sync::Mutex::new(stdin),
            next_id: AtomicI64::new(1),
            waiting: Mutex::new(HashMap::new()),
            thread_id: tokio::sync::Mutex::new(None),
            alive: AtomicBool::new(true),
            busy: AtomicBool::new(false),
            cwd,
            changes: Mutex::new(HashMap::new()),
            last_message: Mutex::new(String::new()),
            _child: Mutex::new(child),
        });

        let reader = codex.clone();
        tauri::async_runtime::spawn(async move {
            let mut lines = BufReader::new(stdout).lines();
            while let Ok(Some(line)) = lines.next_line().await {
                if let Ok(message) = serde_json::from_str::<Value>(&line) {
                    reader.clone().receive(&app, &shared, message);
                }
            }
            reader.alive.store(false, Ordering::SeqCst);
            for (_, waiter) in reader.waiting.lock().unwrap().drain() {
                let _ = waiter.send(Err("Codex stopped.".into()));
            }
            if reader.busy.swap(false, Ordering::SeqCst) {
                reader.emit(&app, "", "failed", "Codex stopped unexpectedly.".into());
            }
        });

        codex
            .request(
                "initialize",
                json!({
                    "clientInfo": { "name": "sidefolk", "title": "Sidefolk", "version": env!("CARGO_PKG_VERSION") },
                    "capabilities": null
                }),
            )
            .await?;
        codex.send(json!({ "method": "initialized" })).await?;
        Ok(codex)
    }

    async fn thread(&self) -> Result<String, String> {
        let mut slot = self.thread_id.lock().await;
        if let Some(id) = slot.as_ref() {
            return Ok(id.clone());
        }
        // "untrusted" asks before anything beyond known-safe reads, which exercises approvals.
        let started = self
            .request(
                "thread/start",
                json!({
                    "cwd": self.cwd,
                    "approvalPolicy": "untrusted",
                    "sandbox": "workspace-write",
                    "ephemeral": true
                }),
            )
            .await?;
        let id = started["thread"]["id"].as_str().ok_or("Codex returned no thread id")?.to_string();
        *slot = Some(id.clone());
        Ok(id)
    }

    async fn send(&self, message: Value) -> Result<(), String> {
        let mut line = message.to_string();
        line.push('\n');
        let mut stdin = self.stdin.lock().await;
        stdin.write_all(line.as_bytes()).await.map_err(|e| e.to_string())?;
        stdin.flush().await.map_err(|e| e.to_string())
    }

    async fn request(&self, method: &str, params: Value) -> Result<Value, String> {
        let id = self.next_id.fetch_add(1, Ordering::SeqCst);
        let (tx, rx) = oneshot::channel();
        self.waiting.lock().unwrap().insert(id, tx);
        self.send(json!({ "id": id, "method": method, "params": params })).await?;
        rx.await.map_err(|_| "Codex stopped.".to_string())?
    }

    fn receive(self: Arc<Self>, app: &AppHandle, shared: &Arc<Shared>, message: Value) {
        let id = message.get("id").cloned();
        let method = message.get("method").and_then(Value::as_str).map(String::from);
        match (id, method) {
            (Some(id), Some(method)) => {
                let (app, shared) = (app.clone(), shared.clone());
                let params = message.get("params").cloned().unwrap_or(Value::Null);
                tauri::async_runtime::spawn(async move {
                    self.approve(&app, &shared, id, &method, params).await;
                });
            }
            (Some(id), None) => {
                let Some(id) = id.as_i64() else { return };
                let Some(waiter) = self.waiting.lock().unwrap().remove(&id) else { return };
                let reply = match message.get("error") {
                    Some(error) => Err(error["message"].as_str().unwrap_or("Codex error").to_string()),
                    None => Ok(message.get("result").cloned().unwrap_or(Value::Null)),
                };
                let _ = waiter.send(reply);
            }
            (None, Some(method)) => self.notify(app, &method, message.get("params").unwrap_or(&Value::Null)),
            (None, None) => {}
        }
    }

    fn emit(&self, app: &AppHandle, session: &str, kind: &'static str, detail: String) {
        bus::emit(
            app,
            AgentEvent {
                source: "codex",
                session: session.to_string(),
                kind,
                detail,
                cwd: self.cwd.display().to_string(),
            },
        );
    }

    fn notify(&self, app: &AppHandle, method: &str, params: &Value) {
        let session = params["threadId"].as_str().unwrap_or_default();
        match method {
            "turn/started" => self.emit(app, session, "think", String::new()),
            "item/started" => {
                let item = &params["item"];
                match item["type"].as_str().unwrap_or_default() {
                    "reasoning" | "agentMessage" | "plan" => self.emit(app, session, "think", String::new()),
                    "commandExecution" => {
                        self.emit(app, session, "run", clip(item["command"].as_str().unwrap_or_default(), 80))
                    }
                    "fileChange" => {
                        let paths = item["changes"]
                            .as_array()
                            .map(|changes| {
                                changes
                                    .iter()
                                    .filter_map(|c| c["path"].as_str())
                                    .map(|p| p.rsplit('/').next().unwrap_or(p))
                                    .collect::<Vec<_>>()
                                    .join(", ")
                            })
                            .unwrap_or_default();
                        if let Some(id) = item["id"].as_str() {
                            self.changes.lock().unwrap().insert(id.to_string(), paths.clone());
                        }
                        self.emit(app, session, "edit", paths);
                    }
                    "webSearch" => self.emit(app, session, "read", "the web".into()),
                    "mcpToolCall" => self.emit(
                        app,
                        session,
                        "tool",
                        format!("{}.{}", item["server"].as_str().unwrap_or("mcp"), item["tool"].as_str().unwrap_or("tool")),
                    ),
                    _ => {}
                }
            }
            "item/completed" => {
                let item = &params["item"];
                if item["type"] == "agentMessage" {
                    let text = item["text"].as_str().unwrap_or_default().to_string();
                    *self.last_message.lock().unwrap() = text.clone();
                    self.emit(app, session, "message", clip(&text, 240));
                }
            }
            "turn/completed" => {
                self.busy.store(false, Ordering::SeqCst);
                let turn = &params["turn"];
                match turn["status"].as_str().unwrap_or_default() {
                    "completed" => {
                        let summary = clip(&self.last_message.lock().unwrap(), 160);
                        self.emit(app, session, "done", summary);
                    }
                    "interrupted" => self.emit(app, session, "failed", "Interrupted.".into()),
                    _ => self.emit(
                        app,
                        session,
                        "failed",
                        clip(turn["error"]["message"].as_str().unwrap_or("The turn failed."), 160),
                    ),
                }
            }
            "error" => {
                let message = params["error"]["message"].as_str().or(params["message"].as_str());
                if let Some(message) = message {
                    self.emit(app, session, "message", clip(message, 160));
                }
            }
            _ => {}
        }
    }

    async fn approve(&self, app: &AppHandle, shared: &Arc<Shared>, id: Value, method: &str, params: Value) {
        let (title, detail) = match method {
            "item/commandExecution/requestApproval" => (
                "Run a command?".to_string(),
                clip(
                    params["command"].as_str().or(params["reason"].as_str()).unwrap_or("a command"),
                    160,
                ),
            ),
            "item/fileChange/requestApproval" => {
                let paths = params["itemId"]
                    .as_str()
                    .and_then(|item| self.changes.lock().unwrap().get(item).cloned())
                    .unwrap_or_default();
                let detail = if paths.is_empty() {
                    params["reason"].as_str().unwrap_or("Codex wants to change files.").to_string()
                } else {
                    paths
                };
                ("Edit files?".to_string(), clip(&detail, 160))
            }
            other => {
                // Not handled in Phase 0: answer so Codex is never left waiting.
                let _ = self
                    .send(json!({ "id": id, "error": { "code": -32601, "message": format!("Sidefolk does not support {other} yet") } }))
                    .await;
                return;
            }
        };
        let session = params["threadId"].as_str().unwrap_or_default().to_string();
        let (ask, answer) = shared.permissions.open("codex");
        let _ = app.emit(
            "permission",
            PermissionAsk {
                id: ask.clone(),
                source: "codex",
                session: session.clone(),
                title,
                detail,
                cwd: self.cwd.display().to_string(),
                can_defer: false,
            },
        );
        self.emit(app, &session, "waiting", String::new());
        let decision = answer.await.unwrap_or(Decision::Deny);
        shared.permissions.close(app, &ask);
        let decision = if decision == Decision::Allow { "accept" } else { "decline" };
        let _ = self.send(json!({ "id": id, "result": { "decision": decision } })).await;
        self.emit(app, &session, "think", String::new());
    }
}
