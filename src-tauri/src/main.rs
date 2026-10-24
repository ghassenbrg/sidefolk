// Prevents an extra console window on Windows release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod bus;
mod claude_setup;
mod codex;
mod crew;
mod hooks;
mod journal;
mod mcp;
mod mcp_setup;
mod models;
mod prefs;
mod overlay;
#[cfg(target_os = "macos")]
mod panel;
mod reminders;
mod sessions;
mod settings;
mod tray;
mod voice;

use std::sync::Arc;

use bus::{Decision, Shared};
use tauri::{AppHandle, Emitter, Manager, State};

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
fn get_crew(shared: State<'_, Arc<Shared>>) -> serde_json::Value {
    shared.crew.lock().unwrap().clone()
}

#[tauri::command]
fn save_crew(app: AppHandle, shared: State<'_, Arc<Shared>>, crew: serde_json::Value) -> Result<(), String> {
    let dir = shared.settings.lock().unwrap().dir.clone();
    crew::save(&dir, &crew).map_err(|e| e.to_string())?;
    *shared.crew.lock().unwrap() = crew;
    let handle = app.clone();
    let _ = app.run_on_main_thread(move || {
        let _ = tray::refresh(&handle);
    });
    Ok(())
}

#[tauri::command]
fn journal_since(shared: State<'_, Arc<Shared>>, since: u64) -> Vec<journal::Entry> {
    shared.journal.since(since)
}

#[tauri::command]
fn list_reminders(shared: State<'_, Arc<Shared>>) -> Vec<reminders::Reminder> {
    shared.reminders.list()
}

#[tauri::command]
fn add_reminder(
    app: AppHandle,
    shared: State<'_, Arc<Shared>>,
    text: String,
    due: u64,
    project: Option<String>,
    from: Option<String>,
) -> Result<reminders::Reminder, String> {
    let from = match from.as_deref() {
        Some("claude") => "claude",
        Some("codex") => "codex",
        _ => "you",
    };
    let reminder = shared
        .reminders
        .add(&text, due, project.as_deref().unwrap_or_default(), from)
        .map_err(|e| e.to_string())?;
    // The overlay and the Settings window both show reminders.
    let _ = app.emit("reminders-changed", ());
    Ok(reminder)
}

#[tauri::command]
fn update_reminder(
    app: AppHandle,
    shared: State<'_, Arc<Shared>>,
    id: String,
    change: reminders::Change,
) -> Result<bool, String> {
    let updated = shared.reminders.update(&id, &change).map_err(|e| e.to_string())?;
    let _ = app.emit("reminders-changed", ());
    Ok(updated)
}

#[tauri::command]
fn remove_reminder(app: AppHandle, shared: State<'_, Arc<Shared>>, id: String) -> Result<Option<reminders::Reminder>, String> {
    let removed = shared.reminders.remove(&id).map_err(|e| e.to_string())?;
    let _ = app.emit("reminders-changed", ());
    Ok(removed)
}

#[tauri::command]
fn restore_reminder(app: AppHandle, shared: State<'_, Arc<Shared>>, reminder: reminders::Reminder) -> Result<(), String> {
    shared.reminders.restore(reminder).map_err(|e| e.to_string())?;
    let _ = app.emit("reminders-changed", ());
    Ok(())
}

fn data_dir(shared: &Shared) -> std::path::PathBuf {
    shared.settings.lock().unwrap().dir.clone()
}

/// Picks a glb and copies it into the models folder; `None` if the user cancelled.
#[tauri::command]
async fn import_model(app: AppHandle, shared: State<'_, Arc<Shared>>) -> Result<Option<String>, String> {
    let Some(path) = models::pick(&app, "model") else { return Ok(None) };
    models::import(&data_dir(&shared), &path).map(Some).map_err(|e| e.to_string())
}

#[tauri::command]
fn list_models(shared: State<'_, Arc<Shared>>) -> Vec<String> {
    models::list(&data_dir(&shared))
}

#[tauri::command]
fn read_model(shared: State<'_, Arc<Shared>>, name: String) -> Result<tauri::ipc::Response, String> {
    models::read(&data_dir(&shared), &name).map_err(|e| e.to_string())
}

/// Picks a photo and asks Claude for matching kit settings; `None` if the user cancelled.
#[tauri::command]
async fn describe_photo(app: AppHandle) -> Result<Option<String>, String> {
    let Some(path) = models::pick(&app, "photo") else { return Ok(None) };
    models::describe_photo(&path).await.map(Some)
}

/// The page's answer to an agent's tool call (see mcp.rs).
#[tauri::command]
fn mcp_reply(shared: State<'_, Arc<Shared>>, id: String, result: serde_json::Value) -> bool {
    shared.replies.resolve(&id, result)
}

/// Shows the overlay for a reminder while the pet is hidden, without un-hiding it for good;
/// `false` puts it back the way the user left it.
#[tauri::command]
fn peek(app: AppHandle, shared: State<'_, Arc<Shared>>, show: bool) {
    let settings = shared.settings.lock().unwrap().value.clone();
    // Menu bar only means no pets on screen; the page sends a notification instead.
    if !settings.hidden || settings.presence == "menubar" {
        return;
    }
    let handle = app.clone();
    let _ = app.run_on_main_thread(move || {
        let _ = overlay::set_visible(&handle, show);
    });
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
    cwd: Option<String>,
) -> Result<String, String> {
    let prompt = prompt.trim();
    if prompt.is_empty() {
        return Err("Tell me what to ask Codex.".into());
    }
    let cwd = cwd.filter(|c| !c.is_empty()).map(std::path::PathBuf::from);
    codex::dispatch(&app, shared.inner().clone(), prompt.to_string(), cwd).await
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
    // `sidefolk --mcp` is the stdio MCP server agents start; it only talks to the running app.
    if std::env::args().any(|arg| arg == "--mcp") {
        return mcp::run_shim();
    }
    // WebKit's allocator (libpas) runs a scavenger thread in this process that woke for every
    // rendered frame, about 2% CPU on its own. `Malloc=1` makes this process use the system
    // allocator instead; web content runs in WebKit's own processes and is unaffected.
    #[cfg(target_os = "macos")]
    if std::env::var_os("Malloc").is_none() {
        // SAFETY: no other threads exist yet.
        unsafe { std::env::set_var("Malloc", "1") };
    }
    let builder = tauri::Builder::default();
    #[cfg(target_os = "macos")]
    let builder = builder.plugin(tauri_nspanel::init());
    builder
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .manage(claude_setup::SetupState::default())
        .manage(mcp_setup::McpSetupState::default())
        .invoke_handler(tauri::generate_handler![
            resolve_permission,
            dispatch,
            overlay_typing,
            ui_log,
            get_settings,
            save_pet,
            get_crew,
            save_crew,
            journal_since,
            list_reminders,
            add_reminder,
            update_reminder,
            remove_reminder,
            restore_reminder,
            peek,
            mcp_reply,
            import_model,
            list_models,
            read_model,
            describe_photo,
            prefs::update_settings,
            prefs::integrations,
            prefs::tray_action,
            prefs::reveal_data_dir,
            prefs::log_error,
            prefs::pet_action,
            prefs::pick_project,
            prefs::app_info,
            prefs::publish_status,
            prefs::get_status,
            voice::speak,
            voice::voices,
            sessions::open_session,
            sessions::terminals,
            prefs::notify,
            prefs::answered,
            prefs::open_tab
        ])
        .setup(move |app| {
            let store = settings::Store::load(settings::data_dir(app.handle())?)?;
            prefs::log_panics(&store.dir);
            let shared = Arc::new(Shared {
                crew: std::sync::Mutex::new(crew::load(&store.dir)),
                status: Default::default(),
                journal: journal::Journal::open(&store.dir),
                replies: Default::default(),
                token: mcp::ensure_token(&store.dir)?,
                reminders: reminders::Reminders::load(&store.dir),
                settings: std::sync::Mutex::new(store),
                permissions: Default::default(),
                codex: Default::default(),
                hosts: Default::default(),
            });
            app.manage(shared.clone());
            // A desktop pet lives in the menu bar, not the Dock or app switcher.
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            overlay::setup(app.handle())?;
            tray::setup(app.handle())?;
            hooks::spawn(app.handle().clone(), shared.clone());
            // The first minute happens in the Sidefolk window: welcome, comfort, connect.
            if !shared.settings.lock().unwrap().value.onboarded {
                prefs::open_at(app.handle(), "welcome")?;
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("Sidefolk failed to start");
}
