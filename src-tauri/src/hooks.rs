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

use crate::bus::{self, AgentEvent, Decision, PermissionAsk, Shared, clip};

pub const PORT: u16 = 47821;
/// How long the pet holds a permission before the terminal prompt takes over.
const PERMISSION_WAIT: Duration = Duration::from_secs(60);

/// Longest command or input a permission card shows; longer ones are cut with an ellipsis.
pub const ACTION_MAX: usize = 2000;

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
            .route("/dev/codex", post(dev_codex))
            .route("/dev/resolve", post(dev_resolve))
            .route("/dev/ui", post(dev_ui));
        let router = router.with_state((app, shared));
        match tokio::net::TcpListener::bind(("127.0.0.1", PORT)).await {
            Ok(listener) => {
                if let Err(error) = axum::serve(listener, router.into_make_service_with_connect_info::<SocketAddr>()).await {
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
    // Remembers where this session runs, for "Open session".
    shared.hosts.locate_claude(&app, &text(&hook, "session_id"), peer.port());
    if let Some(event) = claude_event(&hook) {
        bus::emit(&app, event);
    }
    // An empty 2xx body tells Claude Code to carry on unchanged.
    StatusCode::OK.into_response()
}

fn claude_event(hook: &Value) -> Option<AgentEvent> {
    let (kind, detail) = match hook.get("hook_event_name")?.as_str()? {
        "SessionStart" => ("start", text(hook, "source")),
        "UserPromptSubmit" => ("prompt", clip(&text(hook, "prompt"), 120)),
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

/// What a permission request would do: its kind, a plain question and the exact action.
/// The action is kept whole (up to `ACTION_MAX`): the card must not hide its meaningful end.
fn describe(tool: &str, input: &Value) -> (&'static str, String, String) {
    let field = |key: &str| input.get(key).and_then(Value::as_str).unwrap_or_default();
    match tool {
        "Bash" => ("command", "Run a command?".into(), clip(field("command"), ACTION_MAX)),
        "Edit" | "MultiEdit" => ("file", "Edit a file?".into(), field("file_path").into()),
        "Write" => ("file", "Write a file?".into(), field("file_path").into()),
        "WebFetch" => ("web", "Open a web page?".into(), clip(field("url"), ACTION_MAX)),
        other => ("tool", format!("Use {other}?"), clip(&input.to_string(), ACTION_MAX)),
    }
}

#[cfg(debug_assertions)]
async fn dev_codex(State((app, shared)): State<Ctx>, headers: HeaderMap, body: Bytes) -> Response {
    let request = match payload(&headers, &body) {
        Ok(request) => request,
        Err(response) => return response,
    };
    let cwd = Some(text(&request, "cwd")).filter(|c| !c.is_empty()).map(Into::into);
    match crate::codex::dispatch(&app, shared, text(&request, "prompt"), cwd).await {
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

/// Forwards an action (for example "prompt" or "dismiss") to the page's dev harness.
#[cfg(debug_assertions)]
async fn dev_ui(State((app, _)): State<Ctx>, headers: HeaderMap, body: Bytes) -> Response {
    match payload(&headers, &body) {
        Ok(request) => {
            let action = text(&request, "action");
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
        self.shared.permissions.close(self.app, &self.id);
    }
}

fn defer_to_app(bundle: &str) -> bool {
    bundle.starts_with("com.jetbrains.")
        || [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "com.mitchellh.ghostty",
            "net.kovidgoyal.kitty",
            "org.alacritty",
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92",
            "dev.zed.Zed",
            "co.zeit.hyper",
            "com.anthropic.claudefordesktop",
        ]
        .contains(&bundle)
}

async fn should_hold(app: &AppHandle, shared: &Shared) -> bool {
    if !shared
        .settings
        .lock()
        .unwrap()
        .value
        .pet_answers_permissions
    {
        return false;
    }
    #[cfg(target_os = "macos")]
    {
        crate::panel::frontmost_bundle(app)
            .await
            .is_some_and(|id| !defer_to_app(&id))
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = app;
        false
    }
}

async fn permission(State((app, shared)): State<Ctx>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, body: Bytes) -> Response {
    let hook = match payload(&headers, &body) {
        Ok(hook) => hook,
        Err(response) => return response,
    };
    shared.hosts.locate_claude(&app, &text(&hook, "session_id"), peer.port());
    if !should_hold(&app, &shared).await {
        if cfg!(debug_assertions) {
            eprintln!("sidefolk: Claude permission deferred to agent UI");
        }
        return StatusCode::OK.into_response();
    }
    let tool = text(&hook, "tool_name");
    let (kind, title, detail) = describe(&tool, &hook["tool_input"]);
    let session = text(&hook, "session_id");
    let project = bus::project_root(&text(&hook, "cwd"));
    bus::note(&app, "claude", &session, &project, "ask", &format!("{title} {detail}"));
    let (id, answer) = shared.permissions.open("claude");
    let _open = OpenRequest {
        app: &app,
        shared: &shared,
        id: id.clone(),
    };
    let _ = app.emit(
        "permission",
        PermissionAsk {
            id,
            source: "claude",
            session: session.clone(),
            title,
            detail,
            project: project.clone(),
            cwd: text(&hook, "cwd"),
            can_defer: true,
            kind,
            expires: crate::journal::now_ms() + PERMISSION_WAIT.as_millis() as u64,
        },
    );
    let decision = tokio::time::timeout(PERMISSION_WAIT, answer).await;
    let answered = match decision {
        Ok(Ok(Decision::Allow)) => "allowed",
        Ok(Ok(Decision::Deny)) => "denied",
        Ok(Ok(Decision::Defer)) => "left to the terminal",
        _ => "not answered on the pet",
    };
    bus::note(&app, "claude", &session, &project, "answer", answered);
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

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn agent_frontends_defer_but_unrelated_apps_do_not() {
        for id in [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "com.mitchellh.ghostty",
            "net.kovidgoyal.kitty",
            "org.alacritty",
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92",
            "dev.zed.Zed",
            "com.jetbrains.intellij",
            "co.zeit.hyper",
            "com.anthropic.claudefordesktop",
        ] {
            assert!(defer_to_app(id), "{id}");
        }
        assert!(!defer_to_app("com.apple.Safari"));
        assert!(!defer_to_app("com.jetbrainsOther"));
    }
}
