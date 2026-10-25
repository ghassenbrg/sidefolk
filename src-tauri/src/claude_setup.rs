//! Claude hook edits are only written after a confirmation, with an exact backup. The hooks are
//! command lines that run Sidefolk's own binary in hook mode (socket.rs):
//! `test -x '<Sidefolk>' && exec '<Sidefolk>' hook || exit 0 # sidefolk-hook`. With Sidefolk quit
//! or deleted they exit 0 and Claude Code carries on as if it weren't installed (docs/V1.md V1-X1).
//! Hooks from older versions (HTTP to 127.0.0.1:47821) are recognised so they can be replaced.
use crate::{bus::Shared, settings::atomic_write};
use serde_json::{Value, json};
use std::{
    fs, io,
    path::{Path, PathBuf},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::{SystemTime, UNIX_EPOCH},
};
use tauri::{AppHandle, Manager};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};

/// Older versions' HTTP hooks.
const PREFIX: &str = "http://127.0.0.1:47821/";
/// Marks Sidefolk's command hooks, so only they are ever changed or removed.
const MARK: &str = "# sidefolk-hook";
/// The events Sidefolk hears. PermissionRequest waits for the user (up to 90 s, as Claude allows).
const EVENTS: [&str; 9] = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "StopFailure", "SessionEnd", "PermissionRequest"];

/// The hook line for this binary.
pub fn hook_line(exe: &Path) -> String {
    let exe = crate::sessions::quote(&exe.to_string_lossy());
    format!("test -x {exe} && exec {exe} hook || exit 0 {MARK}")
}

fn legacy(handler: &Value) -> bool {
    handler.get("url").and_then(Value::as_str).is_some_and(|url| url.starts_with(PREFIX))
}

fn ours(handler: &Value) -> bool {
    legacy(handler) || handler.get("command").and_then(Value::as_str).is_some_and(|c| c.ends_with(MARK))
}

/// What's installed: nothing, the hooks for this binary, or ones that need repair (an older
/// version's, or a Sidefolk that has moved since).
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Installed {
    Missing,
    Current,
    NeedsRepair,
}

/// Current only when every event has exactly the handler setup writes (this binary, unfiltered,
/// with its timeout) and nothing else of ours is anywhere: a missing PermissionRequest or a
/// matcher someone added would quietly stop requests reaching Pip.
pub fn state(value: &Value, exe: &Path) -> Installed {
    let events = value.get("hooks").and_then(Value::as_object);
    let ours_in = |groups: &Value| -> Vec<(Value, Value)> {
        groups.as_array().into_iter().flatten().flat_map(|group| {
            let matcher = group.get("matcher").cloned().unwrap_or(Value::Null);
            group.get("hooks").and_then(Value::as_array).into_iter().flatten().filter(|h| ours(h)).map(move |h| (matcher.clone(), h.clone()))
        }).collect()
    };
    let all: Vec<(&String, Vec<(Value, Value)>)> = events.into_iter().flatten().map(|(event, groups)| (event, ours_in(groups))).filter(|(_, found)| !found.is_empty()).collect();
    if all.is_empty() {
        return Installed::Missing;
    }
    let expected = template(exe);
    let exact = all.len() == EVENTS.len()
        && all.iter().all(|(event, found)| {
            let want = &expected["hooks"][event.as_str()][0]["hooks"][0];
            found.len() == 1 && (found[0].0.is_null() || found[0].0.as_str() == Some("")) && !want.is_null() && found[0].1 == *want
        });
    if exact { Installed::Current } else { Installed::NeedsRepair }
}

/// The hooks to add for this binary.
fn template(exe: &Path) -> Value {
    let line = hook_line(exe);
    let mut events = serde_json::Map::new();
    for event in EVENTS {
        let timeout = if event == "PermissionRequest" { 90 } else { 5 };
        events.insert(event.into(), json!([{ "hooks": [{ "type": "command", "command": line, "timeout": timeout }] }]));
    }
    json!({ "hooks": events })
}

/// A Sidefolk started from a disk image or Downloads runs from a random read-only copy (App
/// Translocation); a hook pointing there breaks as soon as it quits.
pub fn translocated(exe: &Path) -> bool {
    exe.to_string_lossy().contains("/AppTranslocation/")
}

pub fn uninstall(mut value: Value) -> Value {
    if let Some(events) = value.get_mut("hooks").and_then(Value::as_object_mut) {
        events.retain(|_, groups| {
            if let Some(groups) = groups.as_array_mut() {
                groups.retain_mut(|group| {
                    if let Some(handlers) = group.get_mut("hooks").and_then(Value::as_array_mut) {
                        handlers.retain(|h| !ours(h));
                        !handlers.is_empty()
                    } else {
                        true
                    }
                });
                !groups.is_empty()
            } else {
                true
            }
        });
        if events.is_empty() {
            value.as_object_mut().unwrap().shift_remove("hooks");
        }
    }
    value
}

pub fn install(value: Value, exe: &Path) -> Value {
    let hooks_index = value.as_object().and_then(|root| root.keys().position(|key| key == "hooks"));
    let mut value = uninstall(value);
    let Some(root) = value.as_object_mut() else {
        return value;
    };
    if !root.contains_key("hooks") && let Some(index) = hooks_index {
        root.shift_insert(index, "hooks".into(), json!({}));
    }
    let Some(events) = root
        .entry("hooks")
        .or_insert_with(|| json!({}))
        .as_object_mut()
    else {
        return value;
    };
    let template = template(exe);
    for (event, groups) in template["hooks"].as_object().unwrap() {
        if let Some(existing) = events
            .entry(event)
            .or_insert_with(|| json!([]))
            .as_array_mut()
        {
            existing.extend(groups.as_array().unwrap().iter().cloned());
        }
    }
    value
}

pub fn is_installed(value: &Value) -> bool {
    state(value, Path::new("")) != Installed::Missing
}

pub fn target(app: &AppHandle) -> Result<PathBuf, String> {
    app.path().home_dir().map(|home| settings_in(&home)).map_err(|e| e.to_string())
}

struct Snapshot {
    path: PathBuf,
    bytes: Option<Vec<u8>>,
    value: Value,
}
fn read(path: &Path) -> io::Result<Snapshot> {
    // Preserve a user's settings symlink instead of replacing it with a regular file.
    let path = match fs::canonicalize(path) {
        Ok(path) => path,
        Err(e) if e.kind() == io::ErrorKind::NotFound => path.to_owned(),
        Err(e) => return Err(e),
    };
    let bytes = match fs::read(&path) {
        Ok(bytes) => Some(bytes),
        Err(e) if e.kind() == io::ErrorKind::NotFound => None,
        Err(e) => return Err(e),
    };
    let value: Value = serde_json::from_slice(bytes.as_deref().unwrap_or(b"{}"))?;
    // Refuse unexpected shapes rather than silently replacing unrelated user content.
    if !value.is_object()
        || value.get("hooks").is_some_and(|hooks| {
            hooks.as_object().is_none_or(|events| {
                events.values().any(|groups| {
                    groups.as_array().is_none_or(|groups| {
                        groups
                            .iter()
                            .any(|group| group.get("hooks").and_then(Value::as_array).is_none())
                    })
                })
            })
        })
    {
        return Err(io::Error::other(
            "Claude settings must be an object with hook event arrays and handler arrays",
        ));
    }
    Ok(Snapshot { path, bytes, value })
}

fn write(snapshot: Snapshot, data_dir: &Path, connect: bool, exe: &Path) -> io::Result<PathBuf> {
    let current = read(&snapshot.path)?;
    if current.bytes != snapshot.bytes {
        return Err(io::Error::other(
            "Claude settings changed while the dialog was open. Please try again.",
        ));
    }
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(io::Error::other)?
        .as_nanos();
    let backup = data_dir
        .join("backups")
        .join(format!("claude-settings-{stamp}.json"));
    atomic_write(&backup, snapshot.bytes.as_deref().unwrap_or(b"{}"))?;
    let value = if connect {
        install(snapshot.value, exe)
    } else {
        uninstall(snapshot.value)
    };
    atomic_write(&snapshot.path, &serde_json::to_vec_pretty(&value)?)?;
    Ok(backup)
}

#[derive(Default)]
pub struct SetupState {
    busy: AtomicBool,
}

pub fn installed(app: &AppHandle) -> Installed {
    let exe = std::env::current_exe().unwrap_or_default();
    target(app).ok().and_then(|path| read(&path).ok()).map_or(Installed::Missing, |s| state(&s.value, &exe))
}

/// Removes Sidefolk's hooks, with a backup, without asking (uninstall; `sidefolk uninstall`).
pub fn remove(settings: &Path, data_dir: &Path) -> io::Result<Option<PathBuf>> {
    let snapshot = read(settings)?;
    if !is_installed(&snapshot.value) {
        return Ok(None);
    }
    write(snapshot, data_dir, false, Path::new("")).map(Some)
}

/// Where Claude Code's settings are, without the app (the `sidefolk uninstall` command).
pub fn default_target() -> PathBuf {
    settings_in(&PathBuf::from(std::env::var_os("HOME").unwrap_or_default()))
}

/// Sidefolk's own override first, then the profile Claude Code itself uses
/// (`CLAUDE_CONFIG_DIR`), so setup and uninstall always change the same file Claude reads.
fn settings_in(home: &Path) -> PathBuf {
    if let Some(path) = std::env::var_os("SIDEFOLK_CLAUDE_SETTINGS") {
        return path.into();
    }
    std::env::var_os("CLAUDE_CONFIG_DIR").map_or_else(|| home.join(".claude"), PathBuf::from).join("settings.json")
}

fn show_error(app: &AppHandle, error: impl std::fmt::Display) {
    eprintln!("sidefolk: Claude setup: {error}");
    let detail = error.to_string();
    let message = if detail.starts_with("Move Sidefolk") {
        "Move Sidefolk to Applications, then reopen it before connecting."
    } else if detail.contains("changed while the dialog") {
        "Claude’s settings changed; reopen the connection dialog and try again."
    } else {
        "I couldn’t finish; check the connection in Settings → Agents."
    };
    app.dialog()
        .message(message)
        .title("Claude Code connection")
        .kind(MessageDialogKind::Error)
        .show(|_| {});
}

fn wants_connect(current: Installed, tools_current: bool, pending_disconnect: bool) -> bool {
    !pending_disconnect && (current != Installed::Current || !tools_current)
}

fn apply_connection(snapshot: Snapshot, dir: &Path, connect: bool, exe: &Path, tools: impl FnOnce() -> io::Result<()>) -> io::Result<PathBuf> {
    let backup = write(snapshot, dir, connect, exe)?;
    tools()?;
    Ok(backup)
}

/// Persistence callbacks finish and release their lock before any external work begins.
fn change_connection(snapshot: Snapshot, dir: &Path, connect: bool, exe: &Path, mut persist: impl FnMut(bool) -> io::Result<()>, tools: impl FnOnce() -> io::Result<()>) -> io::Result<PathBuf> {
    persist(!connect)?;
    let backup = apply_connection(snapshot, dir, connect, exe, tools)?;
    persist(false)?;
    Ok(backup)
}

pub fn confirm(app: &AppHandle) {
    if app.state::<SetupState>().busy.swap(true, Ordering::SeqCst) {
        return;
    }
    let snapshot = target(app).and_then(|path| read(&path).map_err(|e| e.to_string()));
    let snapshot = match snapshot {
        Ok(snapshot) => snapshot,
        Err(error) => {
            app.state::<SetupState>()
                .busy
                .store(false, Ordering::SeqCst);
            show_error(app, error);
            return;
        }
    };
    let exe = std::env::current_exe().unwrap_or_default();
    if translocated(&exe) {
        app.state::<SetupState>().busy.store(false, Ordering::SeqCst);
        show_error(app, "Move Sidefolk to your Applications folder and open it from there first. Connected from here, Claude Code would lose it as soon as Sidefolk quits.");
        return;
    }
    // Hooks from an older version, or a Sidefolk that moved: connecting again repairs them.
    let current = state(&snapshot.value, &exe);
    let tools = crate::mcp_setup::Agent::Claude;
    let pending = app.state::<Arc<Shared>>().settings.lock().unwrap().value.claude_disconnect_pending;
    let connect = wants_connect(current, tools.current(), pending);
    let verb = if pending { "Finish disconnecting" } else if current == Installed::NeedsRepair || (current == Installed::Current && connect) { "Repair" } else if connect { "Connect" } else { "Disconnect" };
    let change = if pending {
        "The previous disconnect did not finish. Sidefolk will finish removing its hooks and companion tools. It will not reconnect them."
    } else if current == Installed::NeedsRepair {
        "Sidefolk's hooks in Claude Code are from an older version, or Sidefolk has moved. Repairing replaces them with ones for this copy, so Claude Code keeps reaching you.\n\nYour other hooks and preferences stay as they are."
    } else if connect {
        "Companions will see Claude Code's work sessions and bring you its requests.\n\nSidefolk adds its own local hooks to Claude Code's settings. Your other hooks and preferences stay as they are."
    } else {
        "Companions will stop seeing Claude Code's work sessions, and its requests stay in Claude Code's own window.\n\nOnly Sidefolk's hooks are removed. Your other hooks and preferences stay as they are."
    };
    let dir = app
        .state::<Arc<Shared>>()
        .settings
        .lock()
        .unwrap()
        .dir
        .clone();
    let message = format!(
        "{change}\n\nThis also {tools_change} Sidefolk’s companion tools through `claude mcp {tools_command} --scope user`. A backup of {} is kept before each CLI change. If either step fails, Settings shows Needs repair; retry to finish.\n\nSettings: {}\nApplies to new Claude Code sessions.\nAn exact backup is saved before writing in:\n{}",
        tools.config().display(),
        snapshot.path.display(),
        dir.join("backups").display(),
        tools_change = if connect { "connects or repairs" } else { "disconnects" },
        tools_command = if connect { "add" } else { "remove" },
    );
    let handle = app.clone();
    app.dialog()
        .message(message)
        .title(format!("{verb} Claude Code?"))
        .buttons(MessageDialogButtons::OkCancelCustom(
            verb.into(),
            "Cancel".into(),
        ))
        .show(move |confirmed| {
            if !confirmed {
                handle
                    .state::<SetupState>()
                    .busy
                    .store(false, Ordering::SeqCst);
                return;
            }
            // File I/O does not hold the UI thread while the dialog closes.
            std::thread::spawn(move || {
                // Persist the user's direction before touching either external config. A failure
                // or an app restart can then offer the same operation instead of reversing it.
                let result = change_connection(snapshot, &dir, connect, &exe, |pending| {
                    let shared = handle.state::<Arc<Shared>>();
                    let mut store = shared.settings.lock().unwrap();
                    store.update(|s| s.claude_disconnect_pending = pending)
                }, || {
                    // A moved executable needs remove then add, each with its own backup.
                    if tools.installed() && (!connect || !tools.current()) {
                        crate::mcp_setup::run(tools, false, &dir.join("backups"))?;
                    }
                    if connect && !tools.current() {
                        crate::mcp_setup::run(tools, true, &dir.join("backups"))?;
                    }
                    Ok(())
                });
                let app = handle.clone();
                let _ = handle.run_on_main_thread(move || {
                    app.state::<SetupState>()
                        .busy
                        .store(false, Ordering::SeqCst);
                    if let Err(error) = crate::tray::refresh(&app) {
                        eprintln!("sidefolk: tray: {error}");
                    }
                    match result {
                        Ok(backup) => eprintln!(
                            "sidefolk: Claude {}ed; backup {}",
                            verb.to_lowercase(),
                            backup.display()
                        ),
                        Err(error) => show_error(&app, error),
                    }
                });
            });
        });
}

#[cfg(test)]
mod tests {
    use super::*;
    fn exe() -> PathBuf {
        PathBuf::from("/Applications/Side folk.app/Contents/MacOS/sidefolk")
    }
    fn user_shape() -> Value {
        serde_json::from_str(r#"{"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"echo ready"}]}]},"enabledPlugins":{"example@market":true},"theme":"dark","permissions":{"allow":["Read"]}}"#).unwrap()
    }
    #[test]
    fn persistence_and_hook_failures_do_not_run_external_work_or_reverse_intent() {
        use std::{cell::Cell, sync::Mutex};
        for failed_at in 0..3 {
            let dir = std::env::temp_dir().join(format!("sidefolk-connect-fault-{}-{failed_at}", std::process::id()));
            fs::create_dir_all(&dir).unwrap();
            let config = dir.join("claude-settings.json");
            fs::write(&config, serde_json::to_vec(&install(user_shape(), &exe())).unwrap()).unwrap();
            let snapshot = read(&config).unwrap();
            let store = Mutex::new(crate::settings::Store::load(dir.join("data"), &crate::store::Problems::default()));
            let persisted = Cell::new(0);
            let external = Cell::new(false);
            if failed_at == 1 { fs::write(&config, b"{}").unwrap(); } // stale hook snapshot
            let result = change_connection(snapshot, &dir, false, &exe(), |pending| {
                let call = persisted.get(); persisted.set(call + 1);
                if (failed_at == 0 && call == 0) || (failed_at == 2 && call == 1) { return Err(io::Error::other("injected settings write failure")); }
                store.lock().unwrap().update(|s| s.claude_disconnect_pending = pending)
            }, || {
                assert!(store.try_lock().is_ok(), "settings lock must be released before external work");
                external.set(true); Ok(())
            });
            assert!(result.is_err());
            assert_eq!(external.get(), failed_at == 2);
            let restarted = crate::settings::Store::load(dir.join("data"), &crate::store::Problems::default());
            assert_eq!(restarted.value.claude_disconnect_pending, failed_at != 0);
            if failed_at == 0 { assert_eq!(state(&read(&config).unwrap().value, &exe()), Installed::Current); }
            if failed_at == 1 { assert_eq!(fs::read(&config).unwrap(), b"{}"); }
            if failed_at == 2 { assert_eq!(read(&config).unwrap().value, user_shape()); assert!(!wants_connect(Installed::Missing, true, restarted.value.claude_disconnect_pending)); }
            fs::remove_dir_all(dir).unwrap();
        }
    }
    #[test]
    fn a_failed_disconnect_keeps_its_direction_after_restart() {
        let dir = std::env::temp_dir().join(format!("sidefolk-disconnect-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let config = dir.join("claude-settings.json");
        let mut store = crate::settings::Store::load(dir.join("data"), &crate::store::Problems::default());
        fs::write(&config, serde_json::to_vec(&install(user_shape(), &exe())).unwrap()).unwrap();
        store.update(|s| s.claude_disconnect_pending = true).unwrap();
        let failed = apply_connection(read(&config).unwrap(), &dir, false, &exe(), || Err(io::Error::other("fake MCP failure")));
        assert!(failed.is_err());
        assert_eq!(state(&read(&config).unwrap().value, &exe()), Installed::Missing);
        let mut restarted = crate::settings::Store::load(dir.join("data"), &crate::store::Problems::default());
        assert!(restarted.value.claude_disconnect_pending);
        let connect = wants_connect(Installed::Missing, true, restarted.value.claude_disconnect_pending);
        assert!(!connect, "retry must not reconnect hooks");
        apply_connection(read(&config).unwrap(), &dir, connect, &exe(), || Ok(())).unwrap();
        restarted.update(|s| s.claude_disconnect_pending = false).unwrap();
        assert_eq!(read(&config).unwrap().value, user_shape());
        assert!(!restarted.value.claude_disconnect_pending);
        fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn the_hook_line_fails_closed_and_quotes_the_path() {
        assert_eq!(hook_line(&exe()), "test -x '/Applications/Side folk.app/Contents/MacOS/sidefolk' && exec '/Applications/Side folk.app/Contents/MacOS/sidefolk' hook || exit 0 # sidefolk-hook");
        assert_eq!(hook_line(Path::new("/tmp/it's")), "test -x '/tmp/it'\\''s' && exec '/tmp/it'\\''s' hook || exit 0 # sidefolk-hook");
    }
    #[test]
    fn empty_settings_and_idempotence() {
        let installed = install(json!({}), &exe());
        assert_eq!(state(&installed, &exe()), Installed::Current);
        assert_eq!(installed["hooks"]["PermissionRequest"][0]["hooks"][0]["timeout"], 90);
        assert_eq!(installed["hooks"]["PreToolUse"][0]["hooks"][0]["type"], "command");
        assert_eq!(serde_json::to_vec(&installed).unwrap(), serde_json::to_vec(&install(installed.clone(), &exe())).unwrap());
        assert_eq!(uninstall(installed), json!({}));
    }
    #[test]
    fn older_http_hooks_and_a_moved_app_need_repair_and_are_replaced() {
        let old = json!({"hooks":{"PreToolUse":[{"hooks":[{"type":"http","url":"http://127.0.0.1:47821/claude/event","timeout":2}]}]}});
        assert_eq!(state(&old, &exe()), Installed::NeedsRepair);
        let repaired = install(old, &exe());
        assert_eq!(state(&repaired, &exe()), Installed::Current);
        assert!(!serde_json::to_string(&repaired).unwrap().contains("47821"));
        assert_eq!(state(&repaired, Path::new("/elsewhere/sidefolk")), Installed::NeedsRepair);
        assert!(translocated(Path::new("/private/var/folders/x/AppTranslocation/ABC/d/Sidefolk.app/Contents/MacOS/sidefolk")));
    }
    #[test]
    fn current_needs_every_event_exactly_as_setup_wrote_it() {
        let good = install(json!({}), &exe());
        // No PermissionRequest handler, with a doubled Stop instead: the count still matches.
        let mut broken = good.clone();
        let permission = broken["hooks"].as_object_mut().unwrap().shift_remove("PermissionRequest").unwrap();
        broken["hooks"]["Stop"][0]["hooks"].as_array_mut().unwrap().push(permission[0]["hooks"][0].clone());
        assert_eq!(state(&broken, &exe()), Installed::NeedsRepair);
        // A matcher someone added, or a shorter timeout, stops requests reaching Pip.
        let mut filtered = good.clone();
        filtered["hooks"]["PermissionRequest"][0]["matcher"] = json!("Bash");
        assert_eq!(state(&filtered, &exe()), Installed::NeedsRepair);
        let mut short = good.clone();
        short["hooks"]["PermissionRequest"][0]["hooks"][0]["timeout"] = json!(5);
        assert_eq!(state(&short, &exe()), Installed::NeedsRepair);
        // Repair puts all of it back.
        assert_eq!(state(&install(broken, &exe()), &exe()), Installed::Current);
    }
    #[test]
    fn preserves_user_shape_and_key_order() {
        let original = user_shape();
        let installed = install(original.clone(), &exe());
        assert!(is_installed(&installed));
        assert_eq!(installed["hooks"]["SessionStart"].as_array().unwrap().len(), 2);
        assert_eq!(serde_json::to_vec(&installed).unwrap(), serde_json::to_vec(&install(installed.clone(), &exe())).unwrap());
        let removed = uninstall(installed);
        assert!(!is_installed(&removed));
        assert_eq!(serde_json::to_vec(&original).unwrap(), serde_json::to_vec(&removed).unwrap());
    }
    #[test]
    fn reinstall_keeps_hooks_key_position() {
        let original = json!({"theme":"dark", "hooks": template(&exe())["hooks"], "enabledPlugins":{}});
        assert_eq!(serde_json::to_vec(&install(original.clone(), &exe())).unwrap(), serde_json::to_vec(&original).unwrap());
    }
    #[test]
    fn removes_only_our_handlers_in_mixed_groups() {
        let value = json!({"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
            {"type":"http","url":"http://127.0.0.1:47821/old"},
            {"type":"http","url":"http://127.0.0.1:478210/other"},
            {"type":"command","command":"echo keep # not-sidefolk-hook-really"},
            {"type":"command","command":"test -x '/x' && exec '/x' hook || exit 0 # sidefolk-hook"},
            {"type":"command","command":"echo keep"}]}]}});
        let removed = uninstall(value);
        assert_eq!(removed["hooks"]["PreToolUse"][0]["hooks"].as_array().unwrap().len(), 3);
        assert_eq!(removed["hooks"]["PreToolUse"][0]["matcher"], "Bash");
    }
    #[test]
    fn filesystem_backup_missing_and_changed_file() {
        let dir = std::env::temp_dir().join(format!("sidefolk-setup-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("claude.json");
        let backup = write(read(&path).unwrap(), &dir, true, &exe()).unwrap();
        assert_eq!(fs::read(backup).unwrap(), b"{}");
        // Uninstall without asking removes them again, with a backup.
        assert!(remove(&path, &dir).unwrap().is_some());
        assert!(!is_installed(&read(&path).unwrap().value));
        assert!(remove(&path, &dir).unwrap().is_none());
        let snapshot = read(&path).unwrap();
        fs::write(&path, b"{\"theme\":\"light\"}").unwrap();
        assert!(write(snapshot, &dir, false, &exe()).is_err());
        assert_eq!(fs::read(&path).unwrap(), b"{\"theme\":\"light\"}");
        fs::write(&path, b"not json").unwrap();
        assert!(read(&path).is_err());
        fs::write(&path, br#"{"hooks": []}"#).unwrap();
        assert!(read(&path).is_err());
        fs::remove_dir_all(dir).unwrap();
    }
    /// Explicitly opt in with a temporary COPY; never fall back to the real home path.
    #[test]
    #[ignore = "requires SIDEFOLK_CLAUDE_SETTINGS pointing at a temporary copy"]
    fn copied_user_settings_round_trip() {
        // Resolved first: a link in /tmp pointing at the real settings must not pass.
        let path = PathBuf::from(std::env::var_os("SIDEFOLK_CLAUDE_SETTINGS").expect("copy path")).canonicalize().unwrap();
        assert!(path.starts_with(std::env::temp_dir().canonicalize().unwrap()) || path.starts_with(Path::new("/tmp").canonicalize().unwrap()));
        let original = read(&path).unwrap();
        let bytes = original.bytes.clone().unwrap();
        let expected = serde_json::to_vec(&uninstall(original.value.clone())).unwrap();
        let dir = path.parent().unwrap();
        let backup = write(original, dir, true, &exe()).unwrap();
        assert_eq!(fs::read(backup).unwrap(), bytes);
        assert!(is_installed(&read(&path).unwrap().value));
        write(read(&path).unwrap(), dir, false, &exe()).unwrap();
        assert_eq!(serde_json::to_vec(&read(&path).unwrap().value).unwrap(), expected);
        atomic_write(&path, &bytes).unwrap();
    }
}
