//! Local endpoint for Claude Code's HTTP hooks. Every hook event becomes an `agent` event
//! for the pet. PermissionRequest is held open until the user answers from the pet, so
//! the decision goes straight back to Claude Code.
//!
//! Hooks are configured in `hooks/claude-settings.json`. Nothing here edits the user's
//! Claude Code settings.

use std::{sync::Arc, time::Duration};

use axum::{
    Router,
    body::Bytes,
    extract::State,
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use serde_json::{Value, json};
use tauri::{AppHandle, Emitter};

use crate::bus::{self, AgentEvent, Decision, PermissionAsk, Shared, clip};

pub const PORT: u16 = 47821;
/// How long the pet holds a permission before the terminal prompt takes over.
const PERMISSION_WAIT: Duration = Duration::from_secs(60);

type Ctx = (AppHandle, Arc<Shared>);

pub fn spawn(app: AppHandle, shared: Arc<Shared>) {
    tauri::async_runtime::spawn(async move {
        let router = Router::new()
            .route("/health", get(|| async { "sidefolk" }))
            .route("/claude/event", post(event))
            .route("/claude/permission", post(permission));
        // Debug builds only: lets scripts drive the pet without clicking it.
        #[cfg(debug_assertions)]
        let router = router.route("/dev/codex", post(dev_codex)).route("/dev/resolve", post(dev_resolve));
        let router = router.with_state((app, shared));
        match tokio::net::TcpListener::bind(("127.0.0.1", PORT)).await {
            Ok(listener) => {
                if let Err(error) = axum::serve(listener, router).await {
                    eprintln!("sidefolk: hook server stopped: {error}");
                }
            }
            Err(error) => eprintln!("sidefolk: cannot listen on 127.0.0.1:{PORT}: {error}"),
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
    value.get(key).and_then(Value::as_str).unwrap_or_default().to_string()
}

async fn event(State((app, _)): State<Ctx>, headers: HeaderMap, body: Bytes) -> Response {
    let hook = match payload(&headers, &body) {
        Ok(hook) => hook,
        Err(response) => return response,
    };
    if let Some(event) = claude_event(&hook) {
        bus::emit(&app, event);
    }
    // An empty 2xx body tells Claude Code to carry on unchanged.
    StatusCode::OK.into_response()
}

fn claude_event(hook: &Value) -> Option<AgentEvent> {
    let (kind, detail) = match hook.get("hook_event_name")?.as_str()? {
        "SessionStart" => ("start", text(hook, "source")),
        "UserPromptSubmit" => ("think", clip(&text(hook, "prompt"), 120)),
        "PreToolUse" => tool_activity(&text(hook, "tool_name"), &hook["tool_input"]),
        "PostToolUse" | "PostToolUseFailure" => ("think", String::new()),
        "Notification" => {
            let message = clip(&text(hook, "message"), 140);
            match text(hook, "notification_type").as_str() {
                "permission_prompt" | "agent_needs_input" | "elicitation_dialog" => ("waiting", message),
                "idle_prompt" => ("idle", message),
                _ => ("message", message),
            }
        }
        "Stop" => ("done", clip(&text(hook, "last_assistant_message"), 160)),
        "StopFailure" => ("failed", text(hook, "error")),
        "SessionEnd" => ("end", text(hook, "reason")),
        _ => return None,
    };
    Some(AgentEvent {
        source: "claude",
        session: text(hook, "session_id"),
        kind,
        detail,
        cwd: text(hook, "cwd"),
    })
}

fn tool_activity(tool: &str, input: &Value) -> (&'static str, String) {
    let field = |key: &str| input.get(key).and_then(Value::as_str).unwrap_or_default();
    let file = |key: &str| field(key).rsplit('/').next().unwrap_or_default().to_string();
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

/// What a permission request would do, phrased for a speech bubble.
fn describe(tool: &str, input: &Value) -> (String, String) {
    let field = |key: &str| input.get(key).and_then(Value::as_str).unwrap_or_default();
    match tool {
        "Bash" => ("Run a command?".into(), clip(field("command"), 160)),
        "Edit" | "MultiEdit" => ("Edit a file?".into(), field("file_path").into()),
        "Write" => ("Write a file?".into(), field("file_path").into()),
        "WebFetch" => ("Open a web page?".into(), clip(field("url"), 160)),
        other => (format!("Use {other}?"), clip(&input.to_string(), 160)),
    }
}

#[cfg(debug_assertions)]
async fn dev_codex(State((app, shared)): State<Ctx>, headers: HeaderMap, body: Bytes) -> Response {
    let request = match payload(&headers, &body) {
        Ok(request) => request,
        Err(response) => return response,
    };
    match crate::codex::dispatch(&app, shared, text(&request, "prompt")).await {
        Ok(thread) => axum::Json(json!({ "thread": thread })).into_response(),
        Err(error) => (StatusCode::CONFLICT, error).into_response(),
    }
}

#[cfg(debug_assertions)]
async fn dev_resolve(State((_, shared)): State<Ctx>, headers: HeaderMap, body: Bytes) -> Response {
    let request = match payload(&headers, &body) {
        Ok(request) => request,
        Err(response) => return response,
    };
    let decision = match text(&request, "decision").as_str() {
        "allow" => Decision::Allow,
        "deny" => Decision::Deny,
        _ => Decision::Defer,
    };
    let resolved = shared.permissions.resolve(&text(&request, "id"), decision);
    axum::Json(json!({ "resolved": resolved })).into_response()
}

/// Removes the bubble if Claude Code hangs up while the user is still deciding.
struct OpenRequest<'a> {
    app: &'a AppHandle,
    shared: &'a Shared,
    id: String,
}

impl Drop for OpenRequest<'_> {
    fn drop(&mut self) {
        self.shared.permissions.close(self.app, &self.id);
    }
}

async fn permission(State((app, shared)): State<Ctx>, headers: HeaderMap, body: Bytes) -> Response {
    let hook = match payload(&headers, &body) {
        Ok(hook) => hook,
        Err(response) => return response,
    };
    let tool = text(&hook, "tool_name");
    let (title, detail) = describe(&tool, &hook["tool_input"]);
    let (id, answer) = shared.permissions.open("claude");
    let _open = OpenRequest { app: &app, shared: &shared, id: id.clone() };
    let _ = app.emit(
        "permission",
        PermissionAsk {
            id,
            source: "claude",
            session: text(&hook, "session_id"),
            title,
            detail,
            cwd: text(&hook, "cwd"),
            can_defer: true,
        },
    );
    let decision = tokio::time::timeout(PERMISSION_WAIT, answer).await;
    let behavior = match decision {
        Ok(Ok(Decision::Allow)) => json!({ "behavior": "allow" }),
        Ok(Ok(Decision::Deny)) => json!({
            "behavior": "deny",
            "message": "The user declined this from the Sidefolk pet."
        }),
        // Deferred, timed out, or dropped: Claude Code shows its own prompt.
        _ => return StatusCode::OK.into_response(),
    };
    axum::Json(json!({
        "hookSpecificOutput": { "hookEventName": "PermissionRequest", "decision": behavior }
    }))
    .into_response()
}
