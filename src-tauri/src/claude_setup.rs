//! Claude hook edits are only written after a tray confirmation, with an exact backup.
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

const PREFIX: &str = "http://127.0.0.1:47821/";
const TEMPLATE: &str = include_str!("../../hooks/claude-settings.json");

fn ours(handler: &Value) -> bool {
    handler
        .get("url")
        .and_then(Value::as_str)
        .is_some_and(|url| url.starts_with(PREFIX))
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

pub fn install(value: Value) -> Value {
    let hooks_index = value.as_object().and_then(|root| root.keys().position(|key| key == "hooks"));
    let mut value = uninstall(value);
    let Some(root) = value.as_object_mut() else {
        return value;
    };
    if !root.contains_key("hooks") {
        if let Some(index) = hooks_index { root.shift_insert(index, "hooks".into(), json!({})); }
    }
    let Some(events) = root
        .entry("hooks")
        .or_insert_with(|| json!({}))
        .as_object_mut()
    else {
        return value;
    };
    let template: Value = serde_json::from_str(TEMPLATE).expect("bundled hooks are JSON");
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
    value
        .get("hooks")
        .and_then(Value::as_object)
        .is_some_and(|events| {
            events
                .values()
                .filter_map(Value::as_array)
                .flatten()
                .any(|group| {
                    group
                        .get("hooks")
                        .and_then(Value::as_array)
                        .is_some_and(|handlers| handlers.iter().any(ours))
                })
        })
}

pub fn target(app: &AppHandle) -> Result<PathBuf, String> {
    if let Some(path) = std::env::var_os("SIDEFOLK_CLAUDE_SETTINGS") {
        return Ok(path.into());
    }
    app.path()
        .home_dir()
        .map(|p| p.join(".claude/settings.json"))
        .map_err(|e| e.to_string())
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

fn write(snapshot: Snapshot, data_dir: &Path, connect: bool) -> io::Result<PathBuf> {
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
        install(snapshot.value)
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

pub fn connected(app: &AppHandle) -> bool {
    target(app)
        .ok()
        .and_then(|path| read(&path).ok())
        .is_some_and(|s| is_installed(&s.value))
}

fn show_error(app: &AppHandle, error: impl std::fmt::Display) {
    eprintln!("sidefolk: Claude setup: {error}");
    app.dialog()
        .message(error.to_string())
        .title("Claude Code connection")
        .kind(MessageDialogKind::Error)
        .show(|_| {});
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
    let connect = !is_installed(&snapshot.value);
    let verb = if connect { "Connect" } else { "Disconnect" };
    let change = if connect {
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
        "{change}\n\nSettings: {}\nApplies to new Claude Code sessions.\nAn exact backup is saved before writing in:\n{}",
        snapshot.path.display(),
        dir.join("backups").display()
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
                let result = write(snapshot, &dir, connect);
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
    fn user_shape() -> Value {
        serde_json::from_str(r#"{"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"echo ready"}]}]},"enabledPlugins":{"example@market":true},"theme":"dark","permissions":{"allow":["Read"]}}"#).unwrap()
    }
    #[test]
    fn empty_settings_and_idempotence() {
        let installed = install(json!({}));
        assert_eq!(installed, serde_json::from_str::<Value>(TEMPLATE).unwrap());
        assert_eq!(
            serde_json::to_vec(&installed).unwrap(),
            serde_json::to_vec(&install(installed.clone())).unwrap()
        );
        assert_eq!(uninstall(installed), json!({}));
    }
    #[test]
    fn preserves_user_shape_and_key_order() {
        let original = user_shape();
        let installed = install(original.clone());
        assert!(is_installed(&installed));
        assert_eq!(
            installed["hooks"]["SessionStart"].as_array().unwrap().len(),
            2
        );
        assert_eq!(
            serde_json::to_vec(&installed).unwrap(),
            serde_json::to_vec(&install(installed.clone())).unwrap()
        );
        let removed = uninstall(installed);
        assert!(!is_installed(&removed));
        assert_eq!(
            serde_json::to_vec(&original).unwrap(),
            serde_json::to_vec(&removed).unwrap()
        );
    }
    #[test]
    fn reinstall_keeps_hooks_key_position() {
        let original = json!({"theme":"dark", "hooks": serde_json::from_str::<Value>(TEMPLATE).unwrap()["hooks"], "enabledPlugins":{}});
        assert_eq!(serde_json::to_vec(&install(original.clone())).unwrap(), serde_json::to_vec(&original).unwrap());
    }
    #[test]
    fn removes_only_our_handlers_in_mixed_groups() {
        let value = json!({"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
            {"type":"http","url":"http://127.0.0.1:47821/old"},
            {"type":"http","url":"http://127.0.0.1:478210/other"},
            {"type":"command","command":"echo keep"}]}]}});
        let removed = uninstall(value);
        assert_eq!(
            removed["hooks"]["PreToolUse"][0]["hooks"]
                .as_array()
                .unwrap()
                .len(),
            2
        );
        assert_eq!(removed["hooks"]["PreToolUse"][0]["matcher"], "Bash");
    }
    #[test]
    fn filesystem_backup_missing_and_changed_file() {
        let dir = std::env::temp_dir().join(format!("sidefolk-setup-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("claude.json");
        let backup = write(read(&path).unwrap(), &dir, true).unwrap();
        assert_eq!(fs::read(backup).unwrap(), b"{}");
        let snapshot = read(&path).unwrap();
        fs::write(&path, b"{\"theme\":\"light\"}").unwrap();
        assert!(write(snapshot, &dir, false).is_err());
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
        let path = PathBuf::from(std::env::var_os("SIDEFOLK_CLAUDE_SETTINGS").expect("copy path"));
        assert!(
            path.starts_with(std::env::temp_dir().canonicalize().unwrap())
                || path.starts_with("/tmp")
        );
        let original = read(&path).unwrap();
        let bytes = original.bytes.clone().unwrap();
        let expected = serde_json::to_vec(&uninstall(original.value.clone())).unwrap();
        let dir = path.parent().unwrap();
        let backup = write(original, dir, true).unwrap();
        assert_eq!(fs::read(backup).unwrap(), bytes);
        assert!(is_installed(&read(&path).unwrap().value));
        write(read(&path).unwrap(), dir, false).unwrap();
        assert_eq!(
            serde_json::to_vec(&read(&path).unwrap().value).unwrap(),
            expected
        );
        atomic_write(&path, &bytes).unwrap();
    }
}
