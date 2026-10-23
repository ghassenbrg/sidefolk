// Prevents an extra console window on Windows release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod bus;
mod codex;
mod hooks;
mod overlay;

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

/// Dev builds only: lets the page report what it is doing to the terminal.
#[tauri::command]
fn ui_log(line: String) {
    if cfg!(debug_assertions) {
        eprintln!("[ui] {line}");
    }
}

fn main() {
    let shared = Arc::new(Shared::default());
    tauri::Builder::default()
        .manage(shared.clone())
        .invoke_handler(tauri::generate_handler![resolve_permission, dispatch, ui_log])
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
