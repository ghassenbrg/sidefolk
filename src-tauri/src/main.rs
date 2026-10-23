// Prevents an extra console window on Windows release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod bus;
mod codex;
mod hooks;
mod overlay;
#[cfg(target_os = "macos")]
mod panel;

use std::sync::Arc;

use bus::{Decision, Shared};
use tauri::{
    AppHandle, State,
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
};

#[tauri::command]
fn resolve_permission(shared: State<'_, Arc<Shared>>, id: String, decision: String) -> bool {
    let decision = match decision.as_str() {
        "allow" => Decision::Allow,
        "deny" => Decision::Deny,
        _ => Decision::Defer,
    };
    shared.permissions.resolve(&id, decision)
}

#[tauri::command]
async fn dispatch(
    app: AppHandle,
    shared: State<'_, Arc<Shared>>,
    prompt: String,
) -> Result<String, String> {
    let prompt = prompt.trim();
    if prompt.is_empty() {
        return Err("Tell me what to ask Codex.".into());
    }
    codex::dispatch(&app, shared.inner().clone(), prompt.to_string()).await
}

/// The bubble's text field opened or closed.
#[tauri::command]
fn overlay_typing(app: AppHandle, typing: bool) {
    overlay::set_typing(&app, typing);
}

/// Dev builds only: lets the page report what it is doing to the terminal. Async so the
/// focus report can wait on the main thread without blocking it.
#[tauri::command]
async fn ui_log(app: AppHandle, line: String, focus: Option<bool>) {
    if !cfg!(debug_assertions) {
        return;
    }
    #[cfg(target_os = "macos")]
    if focus == Some(true) {
        return eprintln!("[ui] {line} {}", panel::focus_report(&app));
    }
    let _ = (&app, focus);
    eprintln!("[ui] {line}");
}

fn main() {
    let shared = Arc::new(Shared::default());
    let builder = tauri::Builder::default();
    #[cfg(target_os = "macos")]
    let builder = builder.plugin(tauri_nspanel::init());
    builder
        .manage(shared.clone())
        .invoke_handler(tauri::generate_handler![resolve_permission, dispatch, overlay_typing, ui_log])
        .setup(move |app| {
            // A desktop pet lives in the menu bar, not the Dock or app switcher.
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            let quit = MenuItem::with_id(app, "quit", "Quit Sidefolk", true, None::<&str>)?;
            let refit = MenuItem::with_id(app, "refit", "Move to this display", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&refit, &quit])?;
            TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .tooltip("Sidefolk")
                .menu(&menu)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "quit" => app.exit(0),
                    "refit" => {
                        let _ = overlay::fit_to_cursor_display(app);
                    }
                    _ => {}
                })
                .build(app)?;

            overlay::setup(app.handle())?;
            hooks::spawn(app.handle().clone(), shared.clone());
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("Sidefolk failed to start");
}
