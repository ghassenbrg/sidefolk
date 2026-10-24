//! Menu and shortcut share the same main-thread actions.
use crate::{bus::Shared, overlay};
use std::sync::{Arc, Mutex};
use tauri::{
    AppHandle, Emitter, Manager,
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::TrayIconBuilder,
};
use tauri_plugin_autostart::ManagerExt;
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};

#[derive(Default)]
pub struct TrayState {
    pub shortcut_error: Mutex<Option<String>>,
}

pub fn setup(app: &AppHandle) -> tauri::Result<()> {
    app.manage(TrayState::default());
    let shortcut = app
        .state::<Arc<Shared>>()
        .settings
        .lock()
        .unwrap()
        .value
        .shortcut
        .clone();
    let _ = register_shortcut(app, &shortcut);
    // A template image: macOS tints it to match light and dark menu bars.
    TrayIconBuilder::with_id("sidefolk")
        .icon(tauri::image::Image::from_bytes(include_bytes!("../icons/tray.png"))?)
        .icon_as_template(true)
        .tooltip("Sidefolk")
        .menu(&menu(app)?)
        .on_menu_event(|app, event| action(app, event.id.as_ref()))
        .build(app)?;
    Ok(())
}

/// Replaces the summon shortcut. On failure the old one stays and the tray shows the error.
pub fn register_shortcut(app: &AppHandle, shortcut: &str) -> Result<(), String> {
    let shortcuts = app.global_shortcut();
    let state = app.state::<TrayState>();
    let previous = app.state::<Arc<Shared>>().settings.lock().unwrap().value.shortcut.clone();
    let _ = shortcuts.unregister_all();
    let register = |keys: &str| {
        shortcuts.on_shortcut(keys, |app, _, event| {
            if event.state == ShortcutState::Pressed {
                let handle = app.clone();
                let _ = app.run_on_main_thread(move || action(&handle, "toggle"));
            }
        })
    };
    match register(shortcut) {
        Ok(()) => {
            *state.shortcut_error.lock().unwrap() = None;
            Ok(())
        }
        Err(error) => {
            let message = format!("Shortcut unavailable ({shortcut}): {error}");
            eprintln!("sidefolk: {message}");
            if previous != shortcut && register(&previous).is_ok() {
                return Err(message);
            }
            *state.shortcut_error.lock().unwrap() = Some(message.clone());
            Err(message)
        }
    }
}

fn menu(app: &AppHandle) -> tauri::Result<Menu<tauri::Wry>> {
    let shared = app.state::<Arc<Shared>>();
    let settings = shared.settings.lock().unwrap().value.clone();
    let hidden = settings.hidden;
    let waiting = shared.status.lock().unwrap()["waiting"].as_array().map_or(0, Vec::len);
    // Requests stay one click away even when no pet is on screen.
    let requests = MenuItem::with_id(
        app,
        "requests",
        match waiting {
            0 => "No requests waiting".to_string(),
            1 => "1 request waiting…".to_string(),
            n => format!("{n} requests waiting…"),
        },
        waiting > 0,
        None::<&str>,
    )?;
    let toggle = MenuItem::with_id(
        app,
        "toggle",
        if hidden { "Show companion" } else { "Hide companion" },
        true,
        None::<&str>,
    )?;
    let call = MenuItem::with_id(app, "call", "Call companion here", true, None::<&str>)?;
    let connected = crate::claude_setup::connected(app);
    let connect = MenuItem::with_id(
        app,
        "claude",
        if connected {
            "Disconnect Claude Code…"
        } else {
            "Connect Claude Code…"
        },
        true,
        None::<&str>,
    )?;
    let refit = MenuItem::with_id(app, "refit", "Move to this display", true, None::<&str>)?;
    let reminder = MenuItem::with_id(app, "new-reminder", "New reminder…", true, None::<&str>)?;
    let preferences = MenuItem::with_id(app, "settings", "Open Sidefolk…", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit Sidefolk", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let separator2 = PredefinedMenuItem::separator(app)?;
    let menu = Menu::with_items(
        app,
        &[&preferences, &requests, &separator, &toggle, &call, &reminder, &separator2, &connect, &refit, &quit],
    )?;
    if let Some(error) = app
        .state::<TrayState>()
        .shortcut_error
        .lock()
        .unwrap()
        .as_ref()
    {
        menu.append(&MenuItem::with_id(
            app,
            "shortcut-error",
            error,
            false,
            None::<&str>,
        )?)?;
    }
    Ok(menu)
}

pub fn refresh(app: &AppHandle) -> tauri::Result<()> {
    if let Some(tray) = app.tray_by_id("sidefolk") {
        tray.set_menu(Some(menu(app)?))?;
        // A count beside the icon: words and numbers, never color alone.
        let waiting = app.state::<Arc<Shared>>().status.lock().unwrap()["waiting"].as_array().map_or(0, Vec::len);
        tray.set_title((waiting > 0).then(|| waiting.to_string()))?;
    }
    Ok(())
}

fn hidden(app: &AppHandle, hidden: bool) -> tauri::Result<()> {
    app.state::<Arc<Shared>>()
        .settings
        .lock()
        .unwrap()
        .update(|s| s.hidden = hidden)?;
    overlay::apply_visibility(app)?;
    if cfg!(debug_assertions) {
        eprintln!("[ui] hidden={hidden}");
    }
    refresh(app)
}

fn summon(app: &AppHandle) -> tauri::Result<()> {
    overlay::fit_to_cursor_display(app)?;
    let window = overlay::overlay(app);
    let cursor = app.cursor_position()?;
    let origin = window.inner_position()?;
    let x = (cursor.x - origin.x as f64) / window.scale_factor()?;
    hidden(app, false)?;
    window.emit("summon", serde_json::json!({ "x": x }))?;
    Ok(())
}

/// Adds or removes a login item (a LaunchAgent), only when the user picks it in Settings.
fn start_at_login(app: &AppHandle) -> tauri::Result<()> {
    let launcher = app.autolaunch();
    let result = if launcher.is_enabled().unwrap_or(false) {
        launcher.disable()
    } else {
        launcher.enable()
    };
    if let Err(error) = result {
        eprintln!("sidefolk: start at login: {error}");
    }
    refresh(app)
}

pub fn action(app: &AppHandle, action: &str) {
    let result = match action {
        "quit" => {
            app.exit(0);
            return;
        }
        "requests" => crate::prefs::open_at(app, "requests"),
        "toggle" => {
            let is_hidden = app
                .state::<Arc<Shared>>()
                .settings
                .lock()
                .unwrap()
                .value
                .hidden;
            if is_hidden {
                summon(app)
            } else {
                hidden(app, true)
            }
        }
        "call" => summon(app),
        "login" => start_at_login(app),
        "settings" => crate::prefs::open(app),
        "show" => {
            let is_hidden = app.state::<Arc<Shared>>().settings.lock().unwrap().value.hidden;
            if is_hidden { hidden(app, false) } else { Ok(()) }
        }
        "new-reminder" => {
            let is_hidden = app.state::<Arc<Shared>>().settings.lock().unwrap().value.hidden;
            if is_hidden {
                let _ = hidden(app, false);
            }
            overlay::overlay(app).emit("pet-action", serde_json::json!({ "action": "new-reminder" }))
        }
        "tools-claude" => {
            crate::mcp_setup::confirm(app, crate::mcp_setup::Agent::Claude);
            return;
        }
        "tools-codex" => {
            crate::mcp_setup::confirm(app, crate::mcp_setup::Agent::Codex);
            return;
        }
        "refit" => overlay::fit_to_cursor_display(app),
        "claude" => {
            crate::claude_setup::confirm(app);
            return;
        }
        _ => return,
    };
    if let Err(error) = result {
        eprintln!("sidefolk: {action}: {error}");
    }
}
