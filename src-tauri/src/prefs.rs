//! The Settings window (settings.html) and what it can change. Writes to the user's agent
//! configs still go through the confirming installers (claude_setup.rs, mcp_setup.rs).
use crate::{bus::Shared, mcp_setup::Agent, overlay};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::Write,
    path::Path,
    sync::Arc,
};
use tauri::{AppHandle, Emitter, Manager, State, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_autostart::ManagerExt;

const WINDOW: &str = "settings";
/// Logs are for the user to read or attach to a bug report; they never leave this Mac.
const MAX_LOG_BYTES: u64 = 1024 * 1024;

pub fn open(app: &AppHandle) -> tauri::Result<()> {
    open_at(app, "")
}

/// Opens the Sidefolk window on a section ("requests", "review:<id>", "welcome", …).
pub fn open_at(app: &AppHandle, tab: &str) -> tauri::Result<()> {
    if let Some(window) = app.get_webview_window(WINDOW) {
        if !tab.is_empty() {
            window.emit("navigate", tab)?;
        }
        window.show()?;
        return window.set_focus();
    }
    let url = if tab.is_empty() { "settings.html".to_string() } else { format!("settings.html?tab={tab}") };
    let window = WebviewWindowBuilder::new(app, WINDOW, WebviewUrl::App(url.into()))
        .title("Sidefolk")
        .inner_size(1040.0, 740.0)
        .min_inner_size(520.0, 480.0)
        .minimizable(false)
        .center()
        .build()?;
    // An accessory app's window opens behind the frontmost app unless it takes focus.
    window.set_focus()
}

/// The overlay asks for the Sidefolk window, e.g. "Review…" on a pet's card.
#[tauri::command]
pub fn open_tab(app: AppHandle, tab: String) -> Result<(), String> {
    if !tab.chars().all(|c| c.is_ascii_alphanumeric() || "-_:.".contains(c)) || tab.len() > 120 {
        return Err("Unknown section".into());
    }
    let handle = app.clone();
    app.run_on_main_thread(move || {
        let _ = open_at(&handle, &tab);
    })
    .map_err(|e| e.to_string())
}

/// A system notification, for Menu bar only (no pet on screen to show the card).
#[tauri::command]
pub fn notify(app: AppHandle, title: String, body: String) -> Result<(), String> {
    use tauri_plugin_notification::NotificationExt;
    app.notification()
        .builder()
        .title(crate::bus::clip(&title, 80))
        .body(crate::bus::clip(&body, 200))
        .show()
        .map_err(|e| e.to_string())
}

/// The overlay applied (or could not apply) an answer sent from the dashboard.
#[tauri::command]
pub fn answered(app: AppHandle, id: String, ok: bool) {
    let _ = app.emit_to(WINDOW, "answered", serde_json::json!({ "id": id, "ok": ok }));
}

#[derive(Deserialize, Default)]
pub struct Change {
    shortcut: Option<String>,
    sleep_after_secs: Option<u64>,
    pet_answers_permissions: Option<bool>,
    hide_in_recordings: Option<bool>,
    onboarded: Option<bool>,
    pet_size: Option<String>,
    calm: Option<bool>,
    large_text: Option<bool>,
    sounds: Option<bool>,
    volume: Option<u8>,
    speak: Option<bool>,
    voice: Option<String>,
    presence: Option<String>,
    detail: Option<String>,
    comfort: Option<String>,
    terminal: Option<String>,
}

/// A choice-valued setting must be one of its choices.
fn check(value: &Option<String>, name: &str, allowed: &[&str]) -> Result<(), String> {
    match value.as_deref() {
        Some(v) if !allowed.contains(&v) => Err(format!("{name} must be one of {}", allowed.join(", "))),
        _ => Ok(()),
    }
}

/// Applies and saves a change from the Settings window or the onboarding card.
#[tauri::command]
pub fn update_settings(app: AppHandle, shared: State<'_, Arc<Shared>>, change: Change) -> Result<crate::settings::Settings, String> {
    check(&change.pet_size, "Pet size", &["small", "medium", "large"])?;
    check(&change.presence, "Desktop presence", &["always", "needed", "menubar"])?;
    check(&change.detail, "Card detail", &["full", "project", "status"])?;
    check(&change.comfort, "Comfort", &["friendly", "professional", "minimal"])?;
    check(&change.terminal, "Terminal", &["auto", "terminal", "iterm", "ghostty"])?;
    if let Some(shortcut) = change.shortcut.as_deref() {
        crate::tray::register_shortcut(&app, shortcut)?;
    }
    if let Some(hide) = change.hide_in_recordings {
        overlay::overlay(&app).set_content_protected(hide).map_err(|e| e.to_string())?;
    }
    let presence_changed = change.presence.is_some();
    let settings = {
        let mut store = shared.settings.lock().unwrap();
        store
            .update(|s| {
                if let Some(shortcut) = change.shortcut {
                    s.shortcut = shortcut;
                }
                if let Some(secs) = change.sleep_after_secs {
                    s.sleep_after_secs = secs.clamp(30, 86_400);
                }
                if let Some(answer) = change.pet_answers_permissions {
                    s.pet_answers_permissions = answer;
                }
                if let Some(hide) = change.hide_in_recordings {
                    s.hide_in_recordings = hide;
                }
                if let Some(done) = change.onboarded {
                    s.onboarded = done;
                }
                if let Some(size) = change.pet_size {
                    s.pet_size = size;
                }
                if let Some(calm) = change.calm {
                    s.calm = calm;
                }
                if let Some(large) = change.large_text {
                    s.large_text = large;
                }
                if let Some(sounds) = change.sounds {
                    s.sounds = sounds;
                }
                if let Some(volume) = change.volume {
                    s.volume = volume.min(100);
                }
                if let Some(speak) = change.speak {
                    s.speak = speak;
                }
                if let Some(voice) = change.voice {
                    s.voice = voice.chars().take(60).collect();
                }
                if let Some(presence) = change.presence {
                    s.presence = presence;
                }
                if let Some(detail) = change.detail {
                    s.detail = detail;
                }
                if let Some(comfort) = change.comfort {
                    s.comfort = comfort;
                }
                if let Some(terminal) = change.terminal {
                    s.terminal = terminal;
                }
            })
            .map_err(|e| e.to_string())?;
        store.value.clone()
    };
    let _ = app.emit("settings-changed", &settings);
    let _ = crate::tray::refresh(&app);
    if presence_changed {
        let handle = app.clone();
        let _ = app.run_on_main_thread(move || {
            let _ = overlay::apply_visibility(&handle);
        });
    }
    Ok(settings)
}

#[derive(Serialize)]
pub struct Integrations {
    claude_hooks: bool,
    claude_tools: bool,
    codex_tools: bool,
    start_at_login: bool,
}

#[tauri::command]
pub fn integrations(app: AppHandle) -> Integrations {
    Integrations {
        claude_hooks: crate::claude_setup::connected(&app),
        claude_tools: Agent::Claude.installed(),
        codex_tools: Agent::Codex.installed(),
        start_at_login: app.autolaunch().is_enabled().unwrap_or(false),
    }
}

/// Runs a tray action that asks for confirmation itself (connecting agents, login item).
#[tauri::command]
pub fn tray_action(app: AppHandle, action: String) -> Result<(), String> {
    if !["claude", "tools-claude", "tools-codex", "login", "settings", "toggle"].contains(&action.as_str()) {
        return Err(format!("Unknown action {action}"));
    }
    let handle = app.clone();
    app.run_on_main_thread(move || crate::tray::action(&handle, &action))
        .map_err(|e| e.to_string())
}

/// Opens the data folder (or its `logs` subfolder) in Finder.
#[tauri::command]
pub fn reveal_data_dir(shared: State<'_, Arc<Shared>>, logs: Option<bool>) -> Result<(), String> {
    let mut dir = shared.settings.lock().unwrap().dir.clone();
    if logs == Some(true) {
        dir = dir.join("logs");
        fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    }
    std::process::Command::new("open").arg(dir).spawn().map(|_| ()).map_err(|e| e.to_string())
}

/// Something for the pets to do, from the Settings window or the tray (see "pet-action" in
/// main.ts): run a command, customize, create a project pet, open the reminder form.
#[tauri::command]
pub fn pet_action(app: AppHandle, action: serde_json::Value) -> Result<(), String> {
    if !action.is_object() {
        return Err("A pet action is an object".into());
    }
    // Only actions meant to be watched bring hidden pets back; answers, renames and looks
    // work while they stay hidden.
    if ["call", "create", "demo", "run", "open-session"].contains(&action["action"].as_str().unwrap_or_default()) {
        // The pets may be hidden; anything they are asked to do should be seen.
        let handle = app.clone();
        let _ = app.run_on_main_thread(move || crate::tray::action(&handle, "show"));
    }
    overlay::overlay(&app).emit("pet-action", action).map_err(|e| e.to_string())
}

/// Picks a folder for a new project pet; returns its git root when it is inside a repository.
#[tauri::command]
pub async fn pick_project(app: AppHandle) -> Option<String> {
    use tauri_plugin_dialog::DialogExt;
    let folder = app.dialog().file().set_title("Choose a project folder").blocking_pick_folder()?.into_path().ok()?;
    let folder = folder.display().to_string();
    let root = crate::bus::project_root(&folder);
    Some(if root.is_empty() { folder } else { root })
}

/// The overlay's live snapshot; kept for the dashboard and forwarded to it.
#[tauri::command]
pub fn publish_status(app: AppHandle, shared: State<'_, Arc<Shared>>, status: serde_json::Value) {
    let waiting = status["waiting"].as_array().map_or(0, Vec::len);
    let before = shared.status.lock().unwrap()["waiting"].as_array().map_or(0, Vec::len);
    *shared.status.lock().unwrap() = status.clone();
    let _ = app.emit_to(WINDOW, "status", status);
    // The menu bar shows how many requests wait, so they stay reachable with the pets hidden.
    if waiting != before {
        let handle = app.clone();
        let _ = app.run_on_main_thread(move || {
            let _ = crate::tray::refresh(&handle);
        });
    }
}

#[tauri::command]
pub fn get_status(shared: State<'_, Arc<Shared>>) -> serde_json::Value {
    shared.status.lock().unwrap().clone()
}

#[derive(Serialize)]
pub struct AppInfo {
    version: &'static str,
    data_dir: String,
}

#[tauri::command]
pub fn app_info(shared: State<'_, Arc<Shared>>) -> AppInfo {
    AppInfo {
        version: env!("CARGO_PKG_VERSION"),
        data_dir: shared.settings.lock().unwrap().dir.display().to_string(),
    }
}

fn append_log(dir: &Path, file: &str, text: &str) {
    let path = dir.join("logs").join(file);
    let _ = fs::create_dir_all(dir.join("logs"));
    // Keep one previous log instead of growing without bound.
    if fs::metadata(&path).is_ok_and(|m| m.len() > MAX_LOG_BYTES) {
        let _ = fs::rename(&path, path.with_extension("old.log"));
    }
    if let Ok(mut log) = fs::OpenOptions::new().create(true).append(true).open(&path) {
        let _ = writeln!(log, "{} {}", crate::journal::now_ms(), text.replace('\n', "\n    "));
    }
}

/// Errors the overlay page could not handle, kept in <data dir>/logs/page.log.
#[tauri::command]
pub fn log_error(shared: State<'_, Arc<Shared>>, message: String) {
    let dir = shared.settings.lock().unwrap().dir.clone();
    append_log(&dir, "page.log", &crate::bus::clip(&message, 2000));
}

/// Writes panics to <data dir>/logs/crash.log before the process ends.
pub fn log_panics(dir: &Path) {
    let dir = dir.to_owned();
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        append_log(&dir, "crash.log", &format!("{info}\n{}", std::backtrace::Backtrace::force_capture()));
        previous(info);
    }));
}
