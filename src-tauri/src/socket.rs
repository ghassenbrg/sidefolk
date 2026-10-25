//! Claude Code hooks and agents' tool calls reach the app over a Unix socket in the private data
//! folder (docs/V1.md V1-X1), not a TCP port another process could take over. Claude Code runs
//! `test -x <Sidefolk> && exec <Sidefolk> hook || exit 0`: Sidefolk's own binary in hook mode
//! forwards the event and prints the answer. When the app isn't running, or was deleted, the hook
//! prints nothing and exits 0, and Claude Code carries on as if Sidefolk weren't installed.
//!
//! One message per connection: `{"hook": <the hook's JSON>}` or `{"mcp": <call>, "token": …}`.
//! Only processes of the same user may connect. The trust boundary is the user account: a process
//! running as the user could already edit Claude Code's settings, so the hook doesn't try to prove
//! the app on the other end is Sidefolk; it only accepts an answer of the exact shape the app sends.

use std::{
    io::{self, Read, Write},
    os::unix::fs::{FileTypeExt, MetadataExt, PermissionsExt},
    path::{Path, PathBuf},
    sync::Arc,
    time::{Duration, Instant},
};

use serde_json::{Value, json};
use tauri::{AppHandle, Emitter};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{UnixListener, UnixStream},
};

use crate::{bus::Shared, sessions::Peer};

/// Largest message read: a hook carries a tool's whole input (a file being written).
const MAX: u64 = 8 * 1024 * 1024;
/// Largest answer the hook accepts (a permission answer is a few hundred bytes).
const REPLY_MAX: usize = 64 * 1024;
/// A hook process waits this long for a permission answer, all told; Claude Code's own limit is 90 s.
const PERMISSION_WAIT: Duration = Duration::from_secs(85);
/// Connections served at once; each may hold a message of up to MAX bytes.
const CONNECTIONS: usize = 32;

pub fn path(data_dir: &Path) -> PathBuf {
    data_dir.join("hook.sock")
}

/// Listens until the app quits. A failure shows in the window (hook_error) instead of only
/// the log.
pub fn spawn(app: AppHandle, shared: Arc<Shared>, data_dir: PathBuf) {
    tauri::async_runtime::spawn(async move {
        let listener = match bind(&data_dir) {
            Ok(listener) => listener,
            Err(error) => {
                let why = format!("Sidefolk can't open its private channel for Claude Code ({error}). Quit any other copy of Sidefolk, or restart your Mac.");
                eprintln!("sidefolk: {why}");
                *shared.hook_error.lock().unwrap() = Some(why);
                let _ = app.emit("integrations-changed", ());
                return;
            }
        };
        let (listener, owner) = listener;
        let slots = Arc::new(tokio::sync::Semaphore::new(CONNECTIONS));
        loop {
            // At capacity, stop accepting until a connection ends rather than queueing memory.
            let Ok(slot) = slots.clone().acquire_owned().await else { return };
            let Ok((stream, _)) = listener.accept().await else { continue };
            let (app, shared) = (app.clone(), shared.clone());
            tauri::async_runtime::spawn(async move {
                let _slot = slot;
                if let Err(error) = serve(&app, &shared, stream, Some(owner)).await
                    && cfg!(debug_assertions)
                {
                    eprintln!("sidefolk: socket: {error}");
                }
            });
        }
    });
}

/// The socket, readable and writable by this user only, in a folder only this user can enter,
/// and the user id it belongs to. A stale socket from a crash is replaced; one a running Sidefolk
/// answers on is not, and neither is anything that isn't a socket. The folder must be a real
/// folder: permissions are never changed through a link.
fn bind(data_dir: &Path) -> io::Result<(UnixListener, u32)> {
    std::fs::create_dir_all(data_dir)?;
    if std::fs::symlink_metadata(data_dir)?.file_type().is_symlink() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "the data folder is a link"));
    }
    std::fs::set_permissions(data_dir, std::fs::Permissions::from_mode(0o700))?;
    let path = path(data_dir);
    if let Ok(found) = std::fs::symlink_metadata(&path) {
        if !found.file_type().is_socket() {
            return Err(io::Error::new(io::ErrorKind::AlreadyExists, "hook.sock is not a socket"));
        }
        if std::os::unix::net::UnixStream::connect(&path).is_ok() {
            return Err(io::Error::new(io::ErrorKind::AddrInUse, "another Sidefolk is answering"));
        }
        std::fs::remove_file(&path)?;
    }
    let listener = UnixListener::bind(&path)?;
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))?;
    // The socket this process just made carries this process's user id.
    let owner = std::fs::symlink_metadata(&path)?.uid();
    Ok((listener, owner))
}

async fn serve(app: &AppHandle, shared: &Shared, mut stream: UnixStream, owner: Option<u32>) -> io::Result<()> {
    let peer = stream.peer_cred()?;
    if owner.is_none_or(|owner| peer.uid() != owner) {
        return Err(io::Error::new(io::ErrorKind::PermissionDenied, "a process of another user"));
    }
    let mut bytes = Vec::new();
    tokio::time::timeout(Duration::from_secs(10), (&mut stream).take(MAX).read_to_end(&mut bytes)).await.map_err(|_| io::Error::new(io::ErrorKind::TimedOut, "no message"))??;
    let message: Value = serde_json::from_slice(&bytes).map_err(io::Error::other)?;
    let reply = if let Some(hook) = message.get("hook") {
        let from = Peer::Pid(peer.pid().unwrap_or_default() as u32);
        if hook.get("hook_event_name").and_then(Value::as_str) == Some("PermissionRequest") {
            crate::hooks::on_permission(app, shared, hook, from).await
        } else {
            crate::hooks::on_event(app, shared, hook, from);
            None
        }
    } else if let Some(call) = message.get("mcp") {
        let token = message.get("token").and_then(Value::as_str).unwrap_or_default();
        Some(if crate::mcp::same(token, &shared.token) { crate::mcp::handle(app, shared, call).await } else { json!({ "text": "Sidefolk refused the call.", "isError": true }) })
    } else {
        None
    };
    if let Some(reply) = reply {
        stream.write_all(reply.to_string().as_bytes()).await?;
    }
    stream.shutdown().await
}

/// One message to the app and its answer, all within `wait`; None when the app isn't there,
/// didn't answer in time, or answered more than REPLY_MAX bytes.
pub fn send(data_dir: &Path, message: &Value, wait: Duration) -> Option<String> {
    let deadline = Instant::now() + wait;
    let left = || deadline.checked_duration_since(Instant::now()).filter(|d| !d.is_zero());
    let mut stream = std::os::unix::net::UnixStream::connect(path(data_dir)).ok()?;
    stream.set_write_timeout(left()).ok()?;
    stream.write_all(message.to_string().as_bytes()).ok()?;
    stream.shutdown(std::net::Shutdown::Write).ok()?;
    let (mut reply, mut chunk) = (Vec::new(), [0u8; 8192]);
    loop {
        // Each read gets only what's left, so a trickle of bytes can't stretch the wait.
        stream.set_read_timeout(Some(left()?)).ok()?;
        match stream.read(&mut chunk) {
            Ok(0) => break,
            Ok(n) if reply.len() + n <= REPLY_MAX => reply.extend_from_slice(&chunk[..n]),
            Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
            _ => return None,
        }
    }
    String::from_utf8(reply).ok()
}

/// `sidefolk hook`: run by Claude Code for every hook event, with the event on stdin. Prints the
/// app's answer for a permission request; prints nothing (Claude Code carries on as usual) when
/// the app isn't running, answers nothing, or anything goes wrong. Always exits 0.
pub fn run_hook(data_dir: &Path) -> i32 {
    let mut input = Vec::new();
    if io::stdin().take(MAX).read_to_end(&mut input).is_ok()
        && let Some(reply) = hook_reply(data_dir, &input)
    {
        print!("{reply}");
    }
    0
}

/// What `sidefolk hook` prints for this input: only a well-formed permission answer, else nothing.
fn hook_reply(data_dir: &Path, input: &[u8]) -> Option<String> {
    let hook = serde_json::from_slice::<Value>(input).ok()?;
    let permission = hook.get("hook_event_name").and_then(Value::as_str) == Some("PermissionRequest");
    let wait = if permission { PERMISSION_WAIT } else { Duration::from_secs(5) };
    let reply = send(data_dir, &json!({ "hook": hook }), wait)?;
    (permission && well_formed(&reply)).then_some(reply)
}

/// Exactly the answer hooks.rs sends: a PermissionRequest decision to allow or deny.
fn well_formed(reply: &str) -> bool {
    serde_json::from_str::<Value>(reply).is_ok_and(|v| {
        let output = &v["hookSpecificOutput"];
        v.as_object().is_some_and(|o| o.len() == 1) && output["hookEventName"] == "PermissionRequest" && matches!(output["decision"]["behavior"].as_str(), Some("allow" | "deny"))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_hook_stays_silent_when_the_app_is_not_there() {
        let dir = std::env::temp_dir().join(format!("sidefolk-socket-none-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        assert_eq!(send(&dir, &json!({ "hook": {} }), Duration::from_millis(200)), None);
        std::fs::remove_dir_all(dir).unwrap();
    }

    /// A stand-in app on the socket: reads one message, answers `reply`.
    fn app_answering(dir: &Path, reply: &'static str) -> std::thread::JoinHandle<Value> {
        let listener = std::os::unix::net::UnixListener::bind(path(dir)).unwrap();
        std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut message = String::new();
            stream.read_to_string(&mut message).unwrap();
            let _ = stream.write_all(reply.as_bytes());
            serde_json::from_str(&message).unwrap()
        })
    }

    #[test]
    fn the_hook_forwards_the_event_and_prints_only_a_real_permission_answer() {
        let dir = std::env::temp_dir().join(format!("sidefolk-socket-hook-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let decision = r#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#;
        let app = app_answering(&dir, decision);
        let input = br#"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}}"#;
        assert_eq!(hook_reply(&dir, input).as_deref(), Some(decision));
        assert_eq!(app.join().unwrap()["hook"]["tool_input"]["command"], "ls");
        std::fs::remove_file(path(&dir)).unwrap();
        // A malformed answer never reaches Claude Code; neither does anything for a plain event.
        for wrong in [r#"{"behavior":"allow"}"#, r#"{"hookSpecificOutput":{}}"#, r#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"ask"}}}"#] {
            let app = app_answering(&dir, wrong);
            assert_eq!(hook_reply(&dir, input), None, "{wrong}");
            app.join().unwrap();
            std::fs::remove_file(path(&dir)).unwrap();
        }
        let app = app_answering(&dir, Box::leak("x".repeat(REPLY_MAX + 1).into_boxed_str()));
        assert_eq!(send(&dir, &json!({}), Duration::from_secs(2)), None);
        app.join().unwrap();
        std::fs::remove_file(path(&dir)).unwrap();
        let app = app_answering(&dir, decision);
        assert_eq!(hook_reply(&dir, br#"{"hook_event_name":"PreToolUse"}"#), None);
        app.join().unwrap();
        // Not JSON, or no app: nothing.
        std::fs::remove_file(path(&dir)).unwrap();
        assert_eq!(hook_reply(&dir, b"not json"), None);
        assert_eq!(hook_reply(&dir, input), None);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn binds_privately_replaces_a_stale_socket_and_never_steals_a_live_one() {
        let dir = std::env::temp_dir().join(format!("sidefolk-socket-bind-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        // A stale socket from a crash.
        drop(std::os::unix::net::UnixListener::bind(path(&dir)).unwrap());
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let (listener, owner) = bind(&dir).unwrap();
            assert_eq!(owner, std::fs::metadata(&dir).unwrap().uid());
            assert_eq!(std::fs::metadata(path(&dir)).unwrap().permissions().mode() & 0o777, 0o600);
            assert_eq!(std::fs::metadata(&dir).unwrap().permissions().mode() & 0o777, 0o700);
            // While it answers, a second bind refuses instead of taking it over.
            let accept = tokio::spawn(async move { listener.accept().await.map(|_| ()) });
            assert_eq!(bind(&dir).unwrap_err().kind(), io::ErrorKind::AddrInUse);
            accept.abort();
        });
        // Something that isn't a socket is never deleted to make room.
        std::fs::remove_file(path(&dir)).unwrap();
        std::fs::write(path(&dir), b"keep me").unwrap();
        assert!(tokio::runtime::Runtime::new().unwrap().block_on(async { bind(&dir).map(|_| ()) }).is_err());
        assert_eq!(std::fs::read(path(&dir)).unwrap(), b"keep me");
        std::fs::remove_dir_all(dir).unwrap();
    }
}
