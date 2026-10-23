//! Menu and shortcut share the same main-thread actions.
use crate::{bus::Shared, overlay};
use std::sync::{Arc, Mutex};
use tauri::{
    AppHandle, Emitter, Manager,
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
};
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
    if let Err(error) = app
        .global_shortcut()
        .on_shortcut(shortcut.as_str(), |app, _, event| {
            if event.state == ShortcutState::Pressed {
                let handle = app.clone();
                let _ = app.run_on_main_thread(move || action(&handle, "toggle"));
            }
        })
    {
        let message = format!("Shortcut unavailable ({shortcut}): {error}");
        eprintln!("sidefolk: {message}");
        *app.state::<TrayState>().shortcut_error.lock().unwrap() = Some(message);
    }
    TrayIconBuilder::with_id("sidefolk")
        .icon(app.default_window_icon().unwrap().clone())
        .tooltip("Sidefolk")
        .menu(&menu(app)?)
        .on_menu_event(|app, event| action(app, event.id.as_ref()))
        .build(app)?;
    Ok(())
}

fn menu(app: &AppHandle) -> tauri::Result<Menu<tauri::Wry>> {
    let hidden = app
        .state::<Arc<Shared>>()
        .settings
        .lock()
        .unwrap()
        .value
        .hidden;
    let toggle = MenuItem::with_id(
        app,
        "toggle",
        if hidden { "Show pet" } else { "Hide pet" },
        true,
        None::<&str>,
    )?;
    let call = MenuItem::with_id(app, "call", "Call pet here", true, None::<&str>)?;
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
    let quit = MenuItem::with_id(app, "quit", "Quit Sidefolk", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&toggle, &call, &connect, &refit, &quit])?;
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
    }
    Ok(())
}

fn hidden(app: &AppHandle, hidden: bool) -> tauri::Result<()> {
    overlay::set_visible(app, !hidden)?;
    app.state::<Arc<Shared>>()
        .settings
        .lock()
        .unwrap()
        .update(|s| s.hidden = hidden)?;
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

pub fn action(app: &AppHandle, action: &str) {
    let result = match action {
        "quit" => {
            app.exit(0);
            return;
        }
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
