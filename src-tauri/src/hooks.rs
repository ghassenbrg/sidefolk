//! Local endpoint for Claude Code's HTTP hooks. Every hook event becomes an `agent` event
//! for the pet. PermissionRequest is held only when the user is away from an agent UI.
//!
//! Hooks are configured in `hooks/claude-settings.json` or through the tray installer.

use std::{net::SocketAddr, sync::Arc, time::Duration};

use axum::{
    Router,
    body::Bytes,
    extract::{ConnectInfo, State},
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use serde_json::{Value, json};
use tauri::{AppHandle, Emitter};

use crate::bus::{self, AgentEvent, Decision, Shared, clip};
use crate::requests::End;
use crate::sessions::Peer;

pub const PORT: u16 = 47821;
/// How long the pet holds a permission before the terminal prompt takes over.
const PERMISSION_WAIT: Duration = Duration::from_secs(60);

type Ctx = (AppHandle, Arc<Shared>);

pub fn spawn(app: AppHandle, shared: Arc<Shared>) {
    tauri::async_runtime::spawn(async move {
        let router = Router::new()
            .route("/health", get(|| async { "sidefolk" }))
            .route("/claude/event", post(event))
            .route("/claude/permission", post(permission))
            .route("/mcp/call", post(crate::mcp::call));
        // Debug builds only: lets scripts drive the pet without clicking it.
        #[cfg(debug_assertions)]
        let router = router
            .route("/dev/resolve", post(dev_resolve))
            .route("/dev/ui", post(dev_ui));
        let router = router.with_state((app.clone(), shared.clone()));
        // Claude Code reaches Sidefolk over the socket now (socket.rs); this port serves only hooks
        // from older versions until they're repaired, so a failure here is only logged.
        let failed = |why: String| eprintln!("sidefolk: {why}");
        match tokio::net::TcpListener::bind(("127.0.0.1", PORT)).await {
            Ok(listener) => {
                if let Err(error) = axum::serve(listener, router.into_make_service_with_connect_info::<SocketAddr>()).await {
                    failed(format!("Sidefolk stopped listening to Claude Code ({error}). Restart Sidefolk."));
                }
            }
            Err(error) => failed(format!("Another app is using port {PORT}, so Sidefolk can't hear Claude Code ({error}). Quit the other copy of Sidefolk, or restart your Mac.")),
        }
    });
}

/// Claude Code posts JSON without an Origin header. Browsers always send Origin on
/// cross-site POSTs and need a CORS preflight for JSON, so web pages cannot feed us events.
fn payload(headers: &HeaderMap, body: &Bytes) -> Result<Value, Response> {
    if headers.contains_key(header::ORIGIN) {
        return Err(StatusCode::FORBIDDEN.into_response());
    }
    let json_body = headers
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .is_some_and(|v| v.starts_with("application/json"));
    if !json_body {
        return Err(StatusCode::UNSUPPORTED_MEDIA_TYPE.into_response());
    }
    serde_json::from_slice(body).map_err(|_| StatusCode::BAD_REQUEST.into_response())
}

fn text(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

async fn event(State((app, shared)): State<Ctx>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, body: Bytes) -> Response {
    let hook = match payload(&headers, &body) {
        Ok(hook) => hook,
        Err(response) => return response,
    };
    on_event(&app, &shared, &hook, Peer::Port(peer.port()));
    // An empty 2xx body tells Claude Code to carry on unchanged.
    StatusCode::OK.into_response()
}

/// A Claude Code hook event, from the socket or the older HTTP hooks.
pub fn on_event(app: &AppHandle, shared: &Shared, hook: &Value, peer: Peer) {
    // Remembers where this session runs, for "Open session" and for routing requests, until it
    // ends.
    if hook.get("hook_event_name").and_then(Value::as_str) == Some("SessionEnd") {
        shared.hosts.forget(&format!("claude:{}", text(hook, "session_id")));
    } else {
        shared.hosts.locate_claude(app, &text(hook, "session_id"), peer);
    }
    if !shared.heard.swap(true, std::sync::atomic::Ordering::Relaxed) {
        let _ = app.emit("integrations-changed", ());
    }
    if let Some(event) = claude_event(hook) {
        bus::emit(app, event);
    }
}

fn claude_event(hook: &Value) -> Option<AgentEvent> {
    let (kind, detail) = match hook.get("hook_event_name")?.as_str()? {
        "SessionStart" => ("start", text(hook, "source")),
        "UserPromptSubmit" => ("prompt", clip(text(hook, "prompt").lines().next().unwrap_or_default(), 500)),
        "PreToolUse" => tool_activity(&text(hook, "tool_name"), &hook["tool_input"]),
        "PostToolUse" | "PostToolUseFailure" => ("think", String::new()),
        "Notification" => {
            let message = clip(&text(hook, "message"), 140);
            match text(hook, "notification_type").as_str() {
                "permission_prompt" | "agent_needs_input" | "elicitation_dialog" => {
                    ("waiting", message)
                }
                "idle_prompt" => ("idle", message),
                _ => ("message", message),
            }
        }
        "Stop" => ("done", clip(&text(hook, "last_assistant_message"), 160)),
        "StopFailure" => ("failed", text(hook, "error")),
        "SessionEnd" => ("end", text(hook, "reason")),
        _ => return None,
    };
    Some(AgentEvent::new(
        "claude",
        &text(hook, "session_id"),
        kind,
        detail,
        &text(hook, "cwd"),
    ))
}

fn tool_activity(tool: &str, input: &Value) -> (&'static str, String) {
    let field = |key: &str| input.get(key).and_then(Value::as_str).unwrap_or_default();
    let file = |key: &str| {
        field(key)
            .rsplit('/')
            .next()
            .unwrap_or_default()
            .to_string()
    };
    match tool {
        "Read" => ("read", file("file_path")),
        "Grep" | "Glob" => ("read", clip(field("pattern"), 60)),
        "WebFetch" => ("read", clip(field("url"), 60)),
        "WebSearch" => ("read", clip(field("query"), 60)),
        "Edit" | "MultiEdit" | "Write" | "NotebookEdit" => ("edit", file("file_path")),
        "Bash" => ("run", clip(field("command"), 80)),
        "Task" | "Agent" => ("think", clip(field("description"), 80)),
        other => ("tool", other.to_string()),
    }
}

#[cfg(debug_assertions)]
async fn dev_resolve(State((app, shared)): State<Ctx>, headers: HeaderMap, body: Bytes) -> Response {
    let request = match payload(&headers, &body) {
        Ok(request) => request,
        Err(response) => return response,
    };
    let decision = match text(&request, "decision").as_str() {
        "allow" => Decision::Allow,
        "deny" => Decision::Deny,
        _ => Decision::Defer,
    };
    let resolved = shared.requests.answer(&text(&request, "id"), decision).is_ok();
    shared.requests.changed(&app);
    axum::Json(json!({ "resolved": resolved })).into_response()
}

/// Forwards an action (for example "prompt" or "dismiss") to the page's dev harness.
#[cfg(debug_assertions)]
async fn dev_ui(State((app, shared)): State<Ctx>, headers: HeaderMap, body: Bytes) -> Response {
    match payload(&headers, &body) {
        Ok(request) => {
            let action = text(&request, "action");
            if action == "notifications" {
                return axum::Json(crate::notifications::notification_status().await).into_response();
            }
            if action == "reminders" {
                return axum::Json(shared.reminders.list()).into_response();
            }
            if ["toggle", "call", "refit"].contains(&action.as_str()) {
                let handle = app.clone();
                let _ = app.run_on_main_thread(move || crate::tray::action(&handle, &action));
            } else {
                let _ = app.emit("dev", action);
            }
            StatusCode::OK.into_response()
        }
        Err(response) => response,
    }
}

/// Removes the bubble if Claude Code hangs up while the user is still deciding.
struct OpenRequest<'a> {
    app: &'a AppHandle,
    shared: &'a Shared,
    id: String,
}

impl Drop for OpenRequest<'_> {
    fn drop(&mut self) {
        self.shared.requests.forget(&self.id);
        let _ = self.app.emit("permission-closed", &self.id);
        self.shared.requests.changed(self.app);
    }
}

/// Whether a request waits on the companion: unless the user turned that off, or is already
/// looking at that very session (docs/V1.md V1-D4). Not knowing where it runs counts as not
/// looking: the companion shows it.
async fn should_hold(app: &AppHandle, shared: &Shared, session: &str) -> bool {
    if !shared.settings.lock().unwrap().value.pet_answers_permissions {
        return false;
    }
    looking_at(app, shared, session).await != Some(true)
}

async fn looking_at(app: &AppHandle, shared: &Shared, session: &str) -> Option<bool> {
    #[cfg(target_os = "macos")]
    let frontmost = crate::panel::frontmost_bundle(app).await;
    #[cfg(not(target_os = "macos"))]
    let frontmost: Option<String> = {
        let _ = app;
        None
    };
    let key = format!("claude:{session}");
    // osascript and ps block (osascript for at most 2 s), so this runs where blocking is allowed.
    tokio::task::block_in_place(|| shared.hosts.focused(&key, frontmost.as_deref()))
}

async fn permission(State((app, shared)): State<Ctx>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, body: Bytes) -> Response {
    let hook = match payload(&headers, &body) {
        Ok(hook) => hook,
        Err(response) => return response,
    };
    match on_permission(&app, &shared, &hook, Peer::Port(peer.port())).await {
        Some(decision) => axum::Json(decision).into_response(),
        None => StatusCode::OK.into_response(),
    }
}

/// A Claude Code permission request, from the socket or the older HTTP hooks. The decision for
/// Claude Code, or None: Claude asks in its own prompt.
pub async fn on_permission(app: &AppHandle, shared: &Shared, hook: &Value, peer: Peer) -> Option<Value> {
    shared.hosts.locate_claude(app, &text(hook, "session_id"), peer);
    if !shared.heard.swap(true, std::sync::atomic::Ordering::Relaxed) {
        let _ = app.emit("integrations-changed", ());
    }
    let session = text(hook, "session_id");
    if !should_hold(app, shared, &session).await {
        if cfg!(debug_assertions) {
            eprintln!("sidefolk: Claude permission deferred to agent UI");
        }
        return None;
    }
    let tool = text(hook, "tool_name");
    let cwd = text(hook, "cwd");
    let project = bus::project_root(&cwd);
    let expires = crate::journal::now_ms() + PERMISSION_WAIT.as_millis() as u64;
    // The tool's input is kept as it came; the card shows it whole or offers no Allow (requests.rs).
    let Some((ask, answer)) = shared.requests.open("claude", &session, &cwd, &project, &tool, hook["tool_input"].clone(), true, expires) else {
        // Already five open for this session: Claude asks in its own prompt.
        return None;
    };
    bus::note(app, "claude", &session, &project, "ask", &clip(&format!("{} {}", ask.shown.title, ask.shown.text), 160));
    let _open = OpenRequest {
        app,
        shared,
        id: ask.id.clone(),
    };
    let _ = app.emit("permission", &ask);
    shared.requests.changed(app);
    // Going to the session hands the request back to its own prompt within a second (V1-D4).
    let watch = async {
        loop {
            tokio::time::sleep(Duration::from_millis(500)).await;
            if looking_at(app, shared, &session).await == Some(true) {
                return;
            }
        }
    };
    let mut answer = answer;
    let end = tokio::select! {
        end = tokio::time::timeout(PERMISSION_WAIT, &mut answer) => end,
        () = watch => {
            if shared.requests.release(&ask.id) {
                let _ = app.emit("permission-released", &ask.id);
                shared.requests.changed(app);
            }
            Ok(answer.await)
        }
    };
    let answered = match end {
        Ok(Ok(End::Answered(Decision::Allow))) => "allowed",
        Ok(Ok(End::Answered(Decision::Deny))) => "denied",
        Ok(Ok(_)) => "left to the terminal",
        _ => "not answered on the pet",
    };
    bus::note(app, "claude", &session, &project, "answer", answered);
    let behavior = match end {
        Ok(Ok(End::Answered(Decision::Allow))) => json!({ "behavior": "allow" }),
        Ok(Ok(End::Answered(Decision::Deny))) => json!({
            "behavior": "deny",
            "message": "The user declined this from the Sidefolk pet."
        }),
        // Released, expired, or dropped: Claude Code shows its own prompt.
        _ => return None,
    };
    Some(json!({
        "hookSpecificOutput": { "hookEventName": "PermissionRequest", "decision": behavior }
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn hook_events_become_agent_events() {
        let event = claude_event(&json!({ "hook_event_name": "UserPromptSubmit", "session_id": "s", "prompt": "add rate limiting", "cwd": "/tmp" })).unwrap();
        assert_eq!((event.kind, event.detail.as_str()), ("prompt", "add rate limiting"));
        let multiline = claude_event(&json!({ "hook_event_name":"UserPromptSubmit", "session_id":"s", "prompt":"Review this\nSECRET second line", "cwd":"/tmp" })).unwrap();
        assert_eq!(crate::bus::journal_detail(multiline.kind, &multiline.detail), "Review this");
        assert!(claude_event(&json!({ "hook_event_name": "Unknown" })).is_none());
    }
}
