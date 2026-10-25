//! Pet tools for agents (MCP). Claude Code and Codex start `sidefolk --mcp` as a stdio MCP
//! server in the session's folder. That process forwards tool calls to the running app over its
//! private socket (socket.rs) with the per-install token, and the folder says which project.
//!
//! The tools: `notify` (say something), `ask` (a question with answer buttons), `remind`
//! (a reminder for the user) and `presence` (is the user around).

use std::{
    io::{self, BufRead, Read, Write},
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};

use axum::{
    body::Bytes,
    extract::State,
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Response},
};
use serde_json::{Value, json};
use tauri::{AppHandle, Emitter};

use crate::bus::{self, Shared, clip};

#[path = "mcp_control.rs"]
mod control;

pub const SERVER: &str = "sidefolk";
const TOKEN_HEADER: &str = "x-sidefolk-token";
/// How long `ask` waits for the user by default, and at most.
const ASK_WAIT: u64 = 120;
const ASK_WAIT_MAX: u64 = 600;
/// notify and remind only need the page to acknowledge.
const PAGE_WAIT: Duration = Duration::from_secs(15);

fn tools() -> Value {
    let mut tools = json!([
        {
            "name": "notify",
            "description": "Say one short sentence to the user through their desktop pet, for example that a long task finished or that you need them soon. Shows a speech bubble; does not wait.",
            "inputSchema": {
                "type": "object",
                "properties": { "text": { "type": "string", "description": "One short sentence." } },
                "required": ["text"]
            }
        },
        {
            "name": "ask",
            "description": "Ask the user a question through their desktop pet and wait for the answer. Use it for decisions you cannot make yourself. Without choices the user can answer Yes, No or type a reply. Returns the answer, or says nobody answered.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "question": { "type": "string" },
                    "session_id": { "type": "string", "maxLength": 200, "description": "Your own session/thread ID if known; omit rather than guess another session." },
                    "choices": { "type": "array", "items": { "type": "string" }, "maxItems": 4, "description": "Up to 4 short answer labels." },
                    "timeout_seconds": { "type": "integer", "minimum": 10, "maximum": ASK_WAIT_MAX, "description": "How long to wait (default 120)." }
                },
                "required": ["question"]
            }
        },
        {
            "name": "remind",
            "description": "Set a reminder for the user. Their desktop pet shows it when it is due, even after restarts.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "text": { "type": "string", "description": "What to remind them of." },
                    "when": { "type": "string", "description": "When, as local ISO 8601 (2026-10-24T15:00) or plain words (\"tomorrow at 9\", \"in 2 hours\")." }
                },
                "required": ["text", "when"]
            }
        },
        {
            "name": "presence",
            "description": "Whether the user is at their computer: active, idle (no input for a few minutes) or away.",
            "inputSchema": { "type": "object", "properties": {} }
        }
    ]);
    tools.as_array_mut().unwrap().extend(control::tools());
    tools
}

// ---------------------------------------------------------------- token

fn token_path(data_dir: &Path) -> PathBuf {
    data_dir.join("token")
}

/// Created once per install; the shim reads it from the same data directory.
pub fn ensure_token(data_dir: &Path) -> io::Result<String> {
    if let Ok(token) = std::fs::read_to_string(token_path(data_dir)) {
        let token = token.trim().to_string();
        if token.len() >= 32 {
            return Ok(token);
        }
    }
    let mut bytes = [0u8; 24];
    std::fs::File::open("/dev/urandom")?.read_exact(&mut bytes)?;
    let token: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    crate::settings::atomic_write(&token_path(data_dir), token.as_bytes())?;
    Ok(token)
}

pub(crate) fn same(a: &str, b: &str) -> bool {
    // Constant time, so the token cannot be guessed byte by byte.
    a.len() == b.len() && a.bytes().zip(b.bytes()).fold(0, |acc, (x, y)| acc | (x ^ y)) == 0
}

// ---------------------------------------------------------------- shim (`sidefolk --mcp`)

/// The app's data directory, computed the way Tauri does, since the shim has no app.
pub(crate) fn shim_data_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("SIDEFOLK_DATA_DIR") {
        return dir.into();
    }
    let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
    let identifier = "dev.sidefolk.companion";
    if cfg!(target_os = "macos") {
        home.join("Library/Application Support").join(identifier)
    } else if cfg!(windows) {
        PathBuf::from(std::env::var_os("APPDATA").unwrap_or_default()).join(identifier)
    } else {
        home.join(".local/share").join(identifier)
    }
}

/// Runs the stdio MCP server until the agent closes stdin.
pub fn run_shim() {
    let data_dir = shim_data_dir();
    let cwd = std::env::current_dir().map(|d| d.display().to_string()).unwrap_or_default();
    let mut client = String::new();
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    for line in stdin.lock().lines() {
        let Ok(line) = line else { break };
        let Ok(message) = serde_json::from_str::<Value>(&line) else { continue };
        let Some(id) = message.get("id").cloned() else { continue }; // notifications
        let params = message.get("params").cloned().unwrap_or(Value::Null);
        let result = match message["method"].as_str().unwrap_or_default() {
            "initialize" => {
                client = params["clientInfo"]["name"].as_str().unwrap_or_default().to_string();
                Ok(json!({
                    "protocolVersion": params["protocolVersion"].as_str().unwrap_or("2025-06-18"),
                    "capabilities": { "tools": {} },
                    "serverInfo": { "name": SERVER, "version": env!("CARGO_PKG_VERSION") },
                    "instructions": "These tools reach the user through the Sidefolk desktop pet that looks after this project. Use notify sparingly, ask only for real decisions, and remind when the user asks you to."
                }))
            }
            "ping" => Ok(json!({})),
            "tools/list" => Ok(json!({ "tools": tools() })),
            "tools/call" => Ok(forward(&data_dir, &client, &cwd, &params)),
            other => Err(json!({ "code": -32601, "message": format!("Unknown method {other}") })),
        };
        let reply = match result {
            Ok(result) => json!({ "jsonrpc": "2.0", "id": id, "result": result }),
            Err(error) => json!({ "jsonrpc": "2.0", "id": id, "error": error }),
        };
        if writeln!(stdout, "{reply}").and_then(|_| stdout.flush()).is_err() {
            break;
        }
    }
}

fn tool_result(text: &str, error: bool) -> Value {
    json!({ "content": [{ "type": "text", "text": text }], "isError": error })
}

/// One HTTP/1.1 request to the app; std only, so the shim starts instantly.
fn forward(data_dir: &Path, client: &str, cwd: &str, params: &Value) -> Value {
    let Ok(token) = std::fs::read_to_string(token_path(data_dir)) else {
        return tool_result("Sidefolk is not set up on this computer (no token found).", true);
    };
    let call = json!({
        "tool": params["name"],
        "arguments": params.get("arguments").cloned().unwrap_or(json!({})),
        "cwd": cwd,
        "client": client,
    });
    // Over the private socket (socket.rs); the token proves this is the install's own shim.
    let message = json!({ "mcp": call, "token": token.trim() });
    let Some(reply) = crate::socket::send(data_dir, &message, Duration::from_secs(ASK_WAIT_MAX + 30)) else {
        return tool_result("Sidefolk is not running, so the pet cannot hear you.", true);
    };
    match serde_json::from_str::<Value>(&reply) {
        Ok(reply) => tool_result(reply["text"].as_str().unwrap_or_default(), reply["isError"] == true),
        Err(_) => tool_result("Sidefolk sent an unreadable reply.", true),
    }
}

// ---------------------------------------------------------------- app endpoint

fn reply(text: impl Into<String>, error: bool) -> Value {
    json!({ "text": text.into(), "isError": error })
}

/// POST /mcp/call from the shim. The page shows the call and answers through `mcp_reply`.
pub async fn call(State((app, shared)): State<(AppHandle, Arc<Shared>)>, headers: HeaderMap, body: Bytes) -> Response {
    if headers.contains_key(header::ORIGIN) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let given = headers.get(TOKEN_HEADER).and_then(|v| v.to_str().ok()).unwrap_or_default();
    if !same(given, &shared.token) {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    let Ok(request) = serde_json::from_slice::<Value>(&body) else {
        return StatusCode::BAD_REQUEST.into_response();
    };
    axum::Json(handle(&app, &shared, &request).await).into_response()
}

/// A tool call from an agent, by either way in (the socket or the older HTTP endpoint), once the
/// caller has proven it holds the install's token. The page shows it and answers.
pub async fn handle(app: &AppHandle, shared: &Shared, request: &Value) -> Value {
    let tool = request["tool"].as_str().unwrap_or_default();
    if control::handles(tool) {
        return match control::handle(app, shared, tool, &request["arguments"]).await {
            Ok(value) => reply(value.to_string(), false),
            Err(error) => reply(error, true),
        };
    }
    let args = &request["arguments"];
    let cwd = request["cwd"].as_str().unwrap_or_default();
    let client = request["client"].as_str().unwrap_or_default().to_lowercase();
    let source = if client.contains("codex") { "codex" } else if client.contains("claude") { "claude" } else { "agent" };
    let field = |key: &str, max: usize| clip(args[key].as_str().unwrap_or_default(), max);

    let (args, wait) = match tool {
        "presence" => return reply(presence(), false),
        "notify" => {
            let text = field("text", 200);
            if text.is_empty() {
                return reply("notify needs some text.", true);
            }
            (json!({ "text": text }), PAGE_WAIT)
        }
        "ask" => {
            let question = field("question", 300);
            if question.is_empty() {
                return reply("ask needs a question.", true);
            }
            let choices: Vec<String> = args["choices"]
                .as_array()
                .map(|c| c.iter().filter_map(Value::as_str).map(|c| clip(c, 24)).filter(|c| !c.is_empty()).take(4).collect())
                .unwrap_or_default();
            let seconds = args["timeout_seconds"].as_u64().unwrap_or(ASK_WAIT).clamp(10, ASK_WAIT_MAX);
            (json!({ "question": question, "choices": choices }), Duration::from_secs(seconds))
        }
        "remind" => {
            let (text, when) = (field("text", 300), field("when", 80));
            if text.is_empty() || when.is_empty() {
                return reply("remind needs text and when.", true);
            }
            (json!({ "text": text, "when": when }), PAGE_WAIT)
        }
        other => return reply(format!("Unknown tool {other}."), true),
    };

    let project = bus::project_root(cwd);
    if tool == "ask" {
        bus::note(app, source, "", &project, "ask", args["question"].as_str().unwrap_or_default());
    }
    let expires = crate::journal::now_ms().saturating_add(wait.as_millis() as u64);
    let session = request["arguments"]["session_id"].as_str().unwrap_or_default().chars().take(200).collect::<String>();
    let call = json!({ "tool": tool, "args": args, "project": project, "cwd": cwd, "source": source, "session": session, "expires": expires });
    let Some((id, answer)) = shared.replies.open(call.clone(), expires) else { return reply("Too many pending calls. Wait for an answer and try again.", true); };
    let _ = app.emit(
        "mcp",
        { let mut call = call; call["id"] = json!(id); call },
    );
    let result = tokio::time::timeout(wait, answer).await;
    shared.replies.close(&id);
    match result {
        Ok(Ok(result)) => {
            if tool == "ask" {
                bus::note(app, source, "", &project, "answer", result["text"].as_str().unwrap_or_default());
            }
            result
        }
        _ => {
            let _ = app.emit("mcp-closed", &id);
            if tool == "ask" {
                bus::note(app, source, "", &project, "answer", "not answered on the pet");
                reply("Nobody answered in time; the user may be away. Decide yourself or ask again later.", false)
            } else {
                reply("The pet did not respond.", true)
            }
        }
    }
}

fn presence() -> String {
    #[cfg(target_os = "macos")]
    {
        let idle = crate::overlay::idle_seconds();
        let state = if idle < 120.0 { "active" } else if idle < 900.0 { "idle" } else { "away" };
        format!("{state} (last keyboard or mouse input {} s ago)", idle.round())
    }
    #[cfg(not(target_os = "macos"))]
    {
        "unknown".into()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn token_is_stable_and_private() {
        let dir = std::env::temp_dir().join(format!("sidefolk-token-{}", std::process::id()));
        let first = ensure_token(&dir).unwrap();
        assert_eq!(first.len(), 48);
        assert_eq!(ensure_token(&dir).unwrap(), first);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(std::fs::metadata(token_path(&dir)).unwrap().permissions().mode() & 0o777, 0o600);
        }
        std::fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn compares_tokens() {
        assert!(same("abc", "abc"));
        assert!(!same("abc", "abd"));
        assert!(!same("abc", "abcd"));
    }
    #[test]
    fn lists_the_tools() {
        let names: Vec<_> = tools().as_array().unwrap().iter().map(|t| t["name"].as_str().unwrap().to_string()).collect();
        assert_eq!(names, ["notify", "ask", "remind", "presence", "sidefolk_status", "sidefolk_control", "sidefolk_reminders", "sidefolk_notes"]);
    }
}
