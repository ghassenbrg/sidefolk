// Prevents an extra console window on Windows release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod bus;
mod claude_setup;
mod codex;
mod hooks;
mod overlay;
#[cfg(target_os = "macos")]
mod panel;
mod settings;
mod tray;

use std::sync::Arc;

use bus::{Decision, Shared};
use tauri::{AppHandle, Manager, State};

#[tauri::command]
fn get_settings(shared: State<'_, Arc<Shared>>) -> settings::Settings {
    shared.settings.lock().unwrap().value.clone()
}

#[tauri::command]
fn save_pet(shared: State<'_, Arc<Shared>>, x: f64) -> Result<(), String> {
    if !x.is_finite() {
        return Err("Pet position must be finite".into());
    }
    shared
        .settings
        .lock()
        .unwrap()
        .update(|s| s.pet_x = Some(x))
        .map_err(|e| e.to_string())
}

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
    let builder = tauri::Builder::default();
    #[cfg(target_os = "macos")]
    let builder = builder.plugin(tauri_nspanel::init());
    builder
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_dialog::init())
        .manage(claude_setup::SetupState::default())
        .invoke_handler(tauri::generate_handler![
            resolve_permission,
            dispatch,
            overlay_typing,
            ui_log,
            get_settings,
            save_pet
        ])
        .setup(move |app| {
            let shared = Arc::new(Shared {
                settings: std::sync::Mutex::new(settings::Store::load(settings::data_dir(
                    app.handle(),
                )?)?),
                permissions: Default::default(),
                codex: Default::default(),
            });
            app.manage(shared.clone());
            // A desktop pet lives in the menu bar, not the Dock or app switcher.
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            overlay::setup(app.handle())?;
            tray::setup(app.handle())?;
            hooks::spawn(app.handle().clone(), shared.clone());
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("Sidefolk failed to start");
}
