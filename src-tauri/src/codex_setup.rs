//! F-14: opt-in, event-only Codex hooks. No CLI calls or hook-trust/config.toml edits.
//! Schema and manual hash trust: https://learn.chatgpt.com/docs/hooks
//! Lead wiring: manage SetupState, register configure_codex, and implement hook-codex as a
//! silent event-only transport. Never route Codex PermissionRequest to Claude's approval path.
use crate::settings::atomic_write;
use serde::Serialize;
use serde_json::{Value, json};
use std::{
    fs, io::{self, Read, Write}, path::{Path, PathBuf},
    sync::{Arc, atomic::{AtomicBool, AtomicU64, Ordering}},
    time::{SystemTime, UNIX_EPOCH},
};
use tauri::{AppHandle, Emitter, Manager, WebviewWindow};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons};

const MARK: &str = "# sidefolk-codex-hook";
const EVENTS: [&str; 8] = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "Interrupt", "SessionEnd"];
const MAX: u64 = 4 * 1024 * 1024;
const TRUST: &str = "Open /hooks in Codex and review and trust Sidefolk's hooks. New or changed hook hashes need your review. Then start a session; Sidefolk waits for its first event. Approvals stay in Codex.";
static NEXT: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Installed { Missing, Current, NeedsRepair }
#[derive(Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Health { Missing, NeedsRepair, AwaitingTrustOrEvent, Listening }
#[derive(Debug, Serialize)]
pub struct Outcome {
    pub status: &'static str,
    pub backup: Option<PathBuf>,
    pub trust_required: bool,
    pub message: &'static str,
}
#[derive(Default)]
pub struct SetupState { busy: Arc<AtomicBool>, pub heard: AtomicBool }
struct Busy(Arc<AtomicBool>);
impl Drop for Busy { fn drop(&mut self) { self.0.store(false, Ordering::SeqCst); } }

/// No shell output or exit status from this observational hook may answer/block an approval.
/// Keep a shell around the child so even a child's nonzero exit becomes exit 0.
pub fn hook_line(exe: &Path) -> String {
    let exe = format!("'{}'", exe.to_string_lossy().replace('\'', "'\\''"));
    format!("test -x {exe} && {exe} hook-codex >/dev/null 2>&1; exit 0 {MARK}")
}
fn ours(handler: &Value) -> bool {
    handler.get("command").and_then(Value::as_str).is_some_and(|line| line.ends_with(MARK))
}
fn template(exe: &Path) -> Value {
    let mut hooks = serde_json::Map::new();
    for event in EVENTS {
        let timeout = if matches!(event, "Interrupt" | "SessionEnd") { 1 } else { 3 };
        hooks.insert(event.into(), json!([{ "hooks": [{ "type": "command", "command": hook_line(exe), "timeout": timeout }] }]));
    }
    json!({ "hooks": hooks })
}
fn validate(value: &Value) -> io::Result<()> {
    if !value.is_object() || value.get("hooks").is_some_and(|hooks| {
        hooks.as_object().is_none_or(|events| events.values().any(|groups| {
            groups.as_array().is_none_or(|groups| groups.iter().any(|group| group.get("hooks").and_then(Value::as_array).is_none()))
        }))
    }) {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "Codex hooks must be an object of event arrays and handler arrays"));
    }
    Ok(())
}

/// Pure removal: preserve unrelated empty groups/events, metadata and key order.
pub fn uninstall(mut value: Value) -> io::Result<Value> {
    validate(&value)?;
    if let Some(events) = value.get_mut("hooks").and_then(Value::as_object_mut) {
        let had_events = !events.is_empty();
        events.retain(|_, groups| {
            let groups = groups.as_array_mut().unwrap();
            let before = groups.len();
            groups.retain_mut(|group| {
                let handlers = group["hooks"].as_array_mut().unwrap();
                let before = handlers.len();
                handlers.retain(|h| !ours(h));
                handlers.len() == before || !handlers.is_empty()
            });
            groups.len() == before || !groups.is_empty()
        });
        if had_events && events.is_empty() { value.as_object_mut().unwrap().shift_remove("hooks"); }
    }
    Ok(value)
}

/// Pure merge: refuse malformed shapes and translocated binaries; never touch hook trust.
pub fn install(value: Value, exe: &Path) -> io::Result<Value> {
    if !exe.is_absolute() || exe.to_str().is_none() || exe.to_string_lossy().contains("/AppTranslocation/") {
        return Err(io::Error::other("Move Sidefolk to Applications and reopen it before connecting Codex."));
    }
    let position = value.as_object().and_then(|v| v.keys().position(|k| k == "hooks"));
    let mut value = uninstall(value)?;
    let root = value.as_object_mut().unwrap();
    if !root.contains_key("hooks") && let Some(position) = position {
        root.shift_insert(position, "hooks".into(), json!({}));
    }
    let events = root.entry("hooks").or_insert_with(|| json!({})).as_object_mut().unwrap();
    for (event, groups) in template(exe)["hooks"].as_object().unwrap() {
        events.entry(event).or_insert_with(|| json!([])).as_array_mut().unwrap().extend(groups.as_array().unwrap().iter().cloned());
    }
    Ok(value)
}

pub fn state(value: &Value, exe: &Path) -> io::Result<Installed> {
    validate(value)?;
    let expected = template(exe);
    let mut found = 0;
    let mut exact = true;
    for (event, groups) in value["hooks"].as_object().into_iter().flatten() {
        let mut count = 0;
        for group in groups.as_array().unwrap() {
            for handler in group["hooks"].as_array().unwrap().iter().filter(|h| ours(h)) {
                count += 1; found += 1;
                exact &= expected["hooks"][event][0]["hooks"][0] == *handler
                    && (group.get("matcher").is_none_or(|m| m == "" || m.is_null()))
                    && group.as_object().is_some_and(|g| g.keys().all(|k| k == "hooks" || k == "matcher"));
            }
        }
        if count != 0 { exact &= count == 1 && EVENTS.contains(&event.as_str()); }
    }
    Ok(if found == 0 { Installed::Missing } else if exact && found == EVENTS.len() { Installed::Current } else { Installed::NeedsRepair })
}

/// Explicit profile arguments let tests resolve CODEX_HOME without mutating process environment.
pub fn target_in(home: &Path, codex_home: Option<&Path>) -> PathBuf {
    codex_home.map_or_else(|| home.join(".codex"), Path::to_owned).join("hooks.json")
}
pub fn target(app: &AppHandle) -> Result<PathBuf, String> {
    let home = app.path().home_dir().map_err(|e| e.to_string())?;
    let profile = std::env::var_os("CODEX_HOME").map(PathBuf::from);
    Ok(target_in(&home, profile.as_deref()))
}

pub struct Snapshot { requested: PathBuf, path: PathBuf, bytes: Option<Vec<u8>>, value: Value }
fn destination(path: &Path) -> io::Result<PathBuf> {
    match fs::canonicalize(path) {
        Ok(resolved) => Ok(resolved),
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            if fs::symlink_metadata(path).is_ok() { return Err(io::Error::other("Codex hooks path contains a dangling link")); }
            let parent = path.parent().ok_or_else(|| io::Error::other("Codex profile has no parent"))?;
            let name = path.file_name().ok_or_else(|| io::Error::other("Invalid Codex hooks path"))?;
            Ok(destination(parent)?.join(name))
        }
        Err(error) => Err(error),
    }
}
pub fn prepare(path: &Path) -> io::Result<Snapshot> {
    if !path.is_absolute() { return Err(io::Error::other("Codex hooks path must be absolute")); }
    let resolved = destination(path)?;
    let bytes = match fs::File::open(&resolved) {
        Ok(file) => {
            let mut bytes = Vec::new(); file.take(MAX + 1).read_to_end(&mut bytes)?;
            if bytes.len() as u64 > MAX { return Err(io::Error::other("Codex hooks file is too large")); }
            Some(bytes)
        }
        Err(e) if e.kind() == io::ErrorKind::NotFound => None,
        Err(e) => return Err(e),
    };
    let value = serde_json::from_slice(bytes.as_deref().unwrap_or(b"{}"))?;
    validate(&value)?;
    Ok(Snapshot { requested: path.into(), path: resolved, bytes, value })
}
pub fn health(path: &Path, exe: &Path, heard_since_configuration: bool) -> io::Result<Health> {
    Ok(match state(&prepare(path)?.value, exe)? {
        Installed::Missing => Health::Missing,
        Installed::NeedsRepair => Health::NeedsRepair,
        Installed::Current if heard_since_configuration => Health::Listening,
        Installed::Current => Health::AwaitingTrustOrEvent,
    })
}
fn unchanged(snapshot: &Snapshot) -> io::Result<()> {
    let current = prepare(&snapshot.requested)?;
    if current.path != snapshot.path || current.bytes != snapshot.bytes {
        return Err(io::Error::other("Codex hooks changed while the dialog was open. Please try again."));
    }
    Ok(())
}

/// Filesystem mutations take explicit paths/snapshot. Only the native confirmed command below
/// should call this for a real profile; uninstall can use remove with its explicit Places.
pub fn apply(snapshot: Snapshot, data_dir: &Path, exe: &Path, connect: bool) -> io::Result<Outcome> {
    let value = if connect { install(snapshot.value.clone(), exe)? } else { uninstall(snapshot.value.clone())? };
    unchanged(&snapshot)?;
    if value == snapshot.value {
        return Ok(Outcome { status: "unchanged", backup: None, trust_required: connect, message: if connect { TRUST } else { "Sidefolk's Codex hooks are disconnected." } });
    }
    let stamp = SystemTime::now().duration_since(UNIX_EPOCH).map_err(io::Error::other)?.as_nanos();
    let backups = data_dir.join("backups"); fs::create_dir_all(&backups)?;
    let suffix = if snapshot.bytes.is_some() { "json" } else { "missing" };
    let backup = backups.join(format!("codex-hooks-{stamp}-{}.{suffix}", NEXT.fetch_add(1, Ordering::Relaxed)));
    let mut options = fs::OpenOptions::new(); options.write(true).create_new(true);
    #[cfg(unix)]
    { use std::os::unix::fs::OpenOptionsExt; options.mode(0o600); }
    let mut file = options.open(&backup)?;
    file.write_all(snapshot.bytes.as_deref().unwrap_or_default())?; file.sync_all()?;
    unchanged(&snapshot)?;
    atomic_write(&snapshot.path, &serde_json::to_vec_pretty(&value)?)?;
    Ok(Outcome { status: if connect { "configured" } else { "disconnected" }, backup: Some(backup), trust_required: connect, message: if connect { TRUST } else { "Sidefolk's Codex hooks are disconnected." } })
}
pub fn remove(path: &Path, data_dir: &Path) -> io::Result<Outcome> {
    apply(prepare(path)?, data_dir, Path::new(""), false)
}

/// Native confirmation is mandatory even when a renderer supplies connect=true.
#[tauri::command]
pub async fn configure_codex(app: AppHandle, window: WebviewWindow, connect: bool) -> Result<Outcome, String> {
    if !matches!(window.label(), "preferences" | "settings") { return Err("Change Codex connections from Sidefolk Settings.".into()); }
    let busy = app.try_state::<SetupState>().ok_or("Codex setup is unavailable")?.busy.clone();
    if busy.swap(true, Ordering::SeqCst) { return Err("A Codex connection change is already in progress.".into()); }
    let _busy = Busy(busy);
    let snapshot = prepare(&target(&app)?).map_err(|e| e.to_string())?;
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    // Check before presenting confirmation, and again inside install/apply.
    if connect { install(snapshot.value.clone(), &exe).map_err(|e| e.to_string())?; }
    let data_dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
    let message = format!("{}\n\nHooks: {}\nExact backups: {}\n\n{}", if connect { "Connect Codex session watching (Beta)? Approvals stay in Codex." } else { "Disconnect Sidefolk's Codex hooks?" }, snapshot.requested.display(), data_dir.join("backups").display(), if connect { TRUST } else { "Only Sidefolk-marked handlers will be removed." });
    let (tx, rx) = tokio::sync::oneshot::channel();
    app.dialog().message(message).title("Codex connection (Beta)")
        .buttons(MessageDialogButtons::OkCancelCustom(if connect { "Connect" } else { "Disconnect" }.into(), "Cancel".into()))
        .show(move |yes| { let _ = tx.send(yes); });
    if !rx.await.unwrap_or(false) {
        return Ok(Outcome { status: "cancelled", backup: None, trust_required: false, message: "No Codex hooks were changed." });
    }
    let outcome = tauri::async_runtime::spawn_blocking(move || apply(snapshot, &data_dir, &exe, connect)).await.map_err(|e| e.to_string())?.map_err(|e| e.to_string())?;
    app.state::<SetupState>().heard.store(false, Ordering::Relaxed);
    let _ = app.emit("integrations-changed", ());
    Ok(outcome)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn absent_hooks_file_keeps_the_parent_identity_shown_in_confirmation() {
        let dir = std::env::temp_dir().join(format!("sidefolk-codex-link-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
        fs::create_dir_all(dir.join("a")).unwrap(); fs::create_dir_all(dir.join("b")).unwrap();
        let link = dir.join("profile");
        std::os::unix::fs::symlink(dir.join("a"), &link).unwrap();
        let snapshot = prepare(&link.join("hooks.json")).unwrap();
        fs::remove_file(&link).unwrap();
        std::os::unix::fs::symlink(dir.join("b"), &link).unwrap();
        assert!(apply(snapshot, &dir.join("data"), Path::new("/Applications/Sidefolk.app/Contents/MacOS/sidefolk"), true).is_err());
        assert!(!dir.join("a/hooks.json").exists() && !dir.join("b/hooks.json").exists());
        fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn merge_remove_and_stale_confirmation_preserve_unrelated_config() {
        let dir = std::env::temp_dir().join(format!("sidefolk-codex-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("hooks.json");
        let original = br#"{"description":"mine","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}]}}"#;
        fs::write(&path, original).unwrap();
        let exe = Path::new("/Applications/Sidefolk.app/Contents/MacOS/sidefolk");
        let first = prepare(&path).unwrap();
        let outcome = apply(first, &dir.join("data"), exe, true).unwrap();
        assert_eq!(fs::read(outcome.backup.unwrap()).unwrap(), original);
        assert_eq!(health(&path, exe, false).unwrap(), Health::AwaitingTrustOrEvent);
        assert_eq!(health(&path, exe, true).unwrap(), Health::Listening);
        let installed = fs::read(&path).unwrap();
        assert_eq!(apply(prepare(&path).unwrap(), &dir.join("data"), exe, true).unwrap().status, "unchanged");
        let stale = prepare(&path).unwrap();
        fs::write(&path, b"{}").unwrap();
        assert!(apply(stale, &dir.join("data"), exe, false).is_err());
        assert_eq!(fs::read(&path).unwrap(), b"{}");
        fs::write(&path, installed).unwrap();
        remove(&path, &dir.join("data")).unwrap();
        assert_eq!(prepare(&path).unwrap().value, serde_json::from_slice::<Value>(original).unwrap());
        fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn rejects_bad_shapes_and_translocation_and_uses_explicit_profiles() {
        let exe = Path::new("/Applications/Sidefolk.app/Contents/MacOS/sidefolk");
        assert!(install(json!({"hooks":{"Stop":{}}}), exe).is_err());
        assert!(install(json!({}), Path::new("/private/AppTranslocation/x/Sidefolk")).is_err());
        assert_eq!(target_in(Path::new("/tmp/home"), Some(Path::new("/tmp/profile"))), Path::new("/tmp/profile/hooks.json"));
        let installed = install(json!({}), exe).unwrap();
        assert_eq!(state(&installed, exe).unwrap(), Installed::Current);
        assert!(hook_line(exe).contains("hook-codex >/dev/null 2>&1; exit 0"));
    }
}
