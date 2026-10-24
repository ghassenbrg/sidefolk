//! Drives Codex through `codex app-server`: newline-delimited JSON-RPC over stdio
//! (no "jsonrpc" field). One app-server process per run of Sidefolk and one thread per
//! working folder, so each project's pet hands work to Codex in that project.
//! Command and file-change approvals are routed to the pet.

use std::{
    collections::{HashMap, HashSet},
    path::PathBuf,
    process::Stdio,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicI64, Ordering},
    },
    time::Duration,
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

/// Codex waits forever for an approval; after this long nobody is coming, so decline.
const APPROVAL_WAIT: Duration = Duration::from_secs(10 * 60);

pub struct Codex {
    stdin: tokio::sync::Mutex<ChildStdin>,
    next_id: AtomicI64,
    waiting: Mutex<HashMap<i64, oneshot::Sender<Reply>>>,
    /// Working folder -> thread id.
    threads: tokio::sync::Mutex<HashMap<PathBuf, String>>,
    /// Thread id -> working folder, for events and approvals.
    folders: Mutex<HashMap<String, String>>,
    /// Threads with a turn in progress.
    busy: Mutex<HashSet<String>>,
    alive: AtomicBool,
    /// Paths touched by each fileChange item, for the approval bubble.
    changes: Mutex<HashMap<String, String>>,
    last_message: Mutex<String>,
    _child: Mutex<Child>,
}

/// Starts a turn in `cwd` (a project folder), or in the playground when it is `None`.
pub async fn dispatch(
    app: &AppHandle,
    shared: Arc<Shared>,
    prompt: String,
    cwd: Option<PathBuf>,
) -> Result<String, String> {
    let cwd = match cwd {
        Some(dir) if dir.is_dir() => dir,
        Some(dir) => return Err(format!("{} is not a folder.", dir.display())),
        None => workdir(app)?,
    };
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
    let thread = codex.thread(&cwd).await?;
    if !codex.busy.lock().unwrap().insert(thread.clone()) {
        return Err("Codex is still working on the last request there.".into());
    }
    let result = async {
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
        Ok(thread.clone())
    }
    .await;
    if result.is_err() {
        codex.busy.lock().unwrap().remove(&thread);
    }
    result
}

/// Where work without a project runs: a scratch folder that SIDEFOLK_WORKDIR can override.
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
    /// A turn is running in this thread.
    pub fn is_busy(&self, thread: &str) -> bool {
        self.busy.lock().unwrap().contains(thread)
    }

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
            threads: Default::default(),
            folders: Default::default(),
            busy: Default::default(),
            alive: AtomicBool::new(true),
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
            let busy: Vec<String> = reader.busy.lock().unwrap().drain().collect();
            for thread in busy {
                reader.emit(&app, &thread, "failed", "Codex stopped unexpectedly.".into());
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

    async fn thread(&self, cwd: &PathBuf) -> Result<String, String> {
        let mut threads = self.threads.lock().await;
        if let Some(id) = threads.get(cwd) {
            return Ok(id.clone());
        }
        // "untrusted" asks before anything beyond known-safe reads, which exercises approvals.
        let started = self
            .request(
                "thread/start",
                json!({
                    "cwd": cwd,
                    "approvalPolicy": "untrusted",
                    "sandbox": "workspace-write",
                    "ephemeral": true
                }),
            )
            .await?;
        let id = started["thread"]["id"].as_str().ok_or("Codex returned no thread id")?.to_string();
        threads.insert(cwd.clone(), id.clone());
        self.folders.lock().unwrap().insert(id.clone(), cwd.display().to_string());
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

    fn folder(&self, thread: &str) -> String {
        self.folders.lock().unwrap().get(thread).cloned().unwrap_or_default()
    }

    fn emit(&self, app: &AppHandle, session: &str, kind: &'static str, detail: String) {
        bus::emit(app, AgentEvent::new("codex", session, kind, detail, &self.folder(session)));
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
                self.busy.lock().unwrap().remove(session);
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
        let (kind, title, detail) = match method {
            "item/commandExecution/requestApproval" => (
                "command",
                "Run a command?".to_string(),
                clip(
                    params["command"].as_str().or(params["reason"].as_str()).unwrap_or("a command"),
                    crate::hooks::ACTION_MAX,
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
                ("file", "Edit files?".to_string(), clip(&detail, crate::hooks::ACTION_MAX))
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
        let cwd = self.folder(&session);
        let project = bus::project_root(&cwd);
        bus::note(app, "codex", &session, &project, "ask", &format!("{title} {detail}"));
        let (ask, answer) = shared.permissions.open("codex");
        let _ = app.emit(
            "permission",
            PermissionAsk {
                id: ask.clone(),
                source: "codex",
                session: session.clone(),
                title,
                detail,
                project: project.clone(),
                cwd,
                can_defer: false,
                kind,
                expires: crate::journal::now_ms() + APPROVAL_WAIT.as_millis() as u64,
            },
        );
        self.emit(app, &session, "waiting", String::new());
        let decision = match tokio::time::timeout(APPROVAL_WAIT, answer).await {
            Ok(answer) => answer.unwrap_or(Decision::Deny),
            Err(_) => {
                self.emit(app, &session, "message", "Nobody answered Codex's question, so I declined it.".into());
                Decision::Deny
            }
        };
        shared.permissions.close(app, &ask);
        let answered = if decision == Decision::Allow { "allowed" } else { "denied" };
        bus::note(app, "codex", &session, &project, "answer", answered);
        let decision = if decision == Decision::Allow { "accept" } else { "decline" };
        let _ = self.send(json!({ "id": id, "result": { "decision": decision } })).await;
        self.emit(app, &session, "think", String::new());
    }
}
