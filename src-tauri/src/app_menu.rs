//! Sidefolk as a normal Mac app: the menu bar menus (with Edit, so copy and paste work in
//! fields), a keyboard shortcut for every section (added with each section), and the Dock icon (hidden on request).
use std::sync::Arc;

use tauri::{
    AppHandle, Emitter, Manager,
    menu::{AboutMetadata, Menu, MenuItem, PredefinedMenuItem, Submenu},
};

use crate::bus::Shared;

pub fn build(app: &AppHandle) -> tauri::Result<Menu<tauri::Wry>> {
    let item = |id: &str, text: &str, keys: Option<&str>| MenuItem::with_id(app, format!("app:{id}"), text, true, keys);
    let about = AboutMetadata {
        name: Some("Sidefolk".into()),
        version: Some(env!("CARGO_PKG_VERSION").into()),
        copyright: Some("© 2026 Ghassen Bargougui".into()),
        ..Default::default()
    };
    let sidefolk = Submenu::with_items(
        app,
        "Sidefolk",
        true,
        &[
            &PredefinedMenuItem::about(app, Some("About Sidefolk"), Some(about))?,
            &PredefinedMenuItem::separator(app)?,
            &item("go:settings", "Settings…", Some("CmdOrCtrl+,"))?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::hide(app, None)?,
            &PredefinedMenuItem::hide_others(app, None)?,
            &PredefinedMenuItem::show_all(app, None)?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::quit(app, Some("Quit Sidefolk"))?,
        ],
    )?;
    let file = Submenu::with_items(
        app,
        "File",
        true,
        &[
            &item("go:reminders:new", "New Reminder", Some("CmdOrCtrl+N"))?,
            &item("go:notes:new", "New Notebook", Some("CmdOrCtrl+Shift+N"))?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::close_window(app, None)?,
        ],
    )?;
    let edit = Submenu::with_items(
        app,
        "Edit",
        true,
        &[
            &item("undo", "Undo", Some("CmdOrCtrl+Z"))?,
            &PredefinedMenuItem::redo(app, None)?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::cut(app, None)?,
            &PredefinedMenuItem::copy(app, None)?,
            &PredefinedMenuItem::paste(app, None)?,
            &PredefinedMenuItem::select_all(app, None)?,
        ],
    )?;
    let view = Submenu::with_items(
        app,
        "View",
        true,
        &[
            &item("go:today", "Today", Some("CmdOrCtrl+1"))?,
            &item("go:reminders", "Reminders", Some("CmdOrCtrl+2"))?,
            &item("go:notes", "Work log", Some("CmdOrCtrl+3"))?,
            &item("go:sessions", "Sessions", Some("CmdOrCtrl+4"))?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::fullscreen(app, None)?,
        ],
    )?;
    let window = Submenu::with_items(
        app,
        "Window",
        true,
        &[
            &PredefinedMenuItem::minimize(app, None)?,
            &PredefinedMenuItem::maximize(app, Some("Zoom"))?,
            &PredefinedMenuItem::separator(app)?,
            &item("companion", "Show Companion", None)?,
        ],
    )?;
    let help = Submenu::with_items(app, "Help", true, &[&item("go:settings:help", "Sidefolk Help", None)?])?;
    Menu::with_items(app, &[&sidefolk, &file, &edit, &view, &window, &help])
}

/// Handles the app menu's own items (ids start with "app:"); tray items are handled in tray.rs.
pub fn handle(app: &AppHandle, id: &str) {
    let Some(id) = id.strip_prefix("app:") else { return };
    let result = if let Some(tab) = id.strip_prefix("go:") {
        crate::prefs::open_at(app, tab)
    } else if id == "undo" {
        if let Some(window) = app.webview_windows().values().find(|window| window.is_focused().unwrap_or(false)) {
            window.emit("undo", ())
        } else { Ok(()) }
    } else if id == "companion" {
        crate::tray::show_companion(app)
    } else {
        Ok(())
    };
    if let Err(error) = result {
        eprintln!("sidefolk: menu {id}: {error}");
    }
}

/// In the Dock and ⌘Tab like any app, unless the user chose "Hide from Dock".
pub fn apply_dock(app: &AppHandle) {
    #[cfg(target_os = "macos")]
    {
        let hidden = app.state::<Arc<Shared>>().settings.lock().unwrap().value.hide_from_dock;
        let _ = app.set_activation_policy(if hidden { tauri::ActivationPolicy::Accessory } else { tauri::ActivationPolicy::Regular });
    }
    #[cfg(not(target_os = "macos"))]
    let _ = app;
}
