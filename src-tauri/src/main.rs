// Prevents an extra console window on Windows release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod actions;
mod app_menu;
mod calendar;
mod bus;
mod claude_setup;
mod crew;
mod hooks;
mod journal;
mod mcp;
mod mcp_setup;
mod prefs;
mod overlay;
#[cfg(target_os = "macos")]
mod panel;
mod reminders;
mod requests;
mod notes;
mod notifications;
mod sessions;
mod series;
mod settings;
mod store;
mod tray;

use std::sync::Arc;

use bus::{Decision, Shared};
use tauri::{AppHandle, Emitter, Manager, State};

#[tauri::command]
fn get_settings(shared: State<'_, Arc<Shared>>) -> settings::Settings {
    shared.settings.lock().unwrap().value.clone()
}

#[tauri::command(async)]
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

#[tauri::command(async)]
fn save_crew(app: AppHandle, shared: State<'_, Arc<Shared>>, crew: serde_json::Value) -> Result<(), String> {
    let dir = shared.settings.lock().unwrap().dir.clone();
    crew::save(&dir, &crew, &shared.problems).map_err(|e| e.to_string())?;
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

#[tauri::command(async)]
fn add_reminder(
    app: AppHandle,
    shared: State<'_, Arc<Shared>>,
    text: String,
    due: u64,
    project: Option<String>,
    from: Option<String>,
    repeat: Option<reminders::Repeat>,
) -> Result<reminders::Reminder, String> {
    let from = match from.as_deref() {
        Some("claude") => "claude",
        Some("codex") => "codex",
        _ => "you",
    };
    let reminder = shared
        .reminders
        .add(&text, due, project.as_deref().unwrap_or_default(), from, repeat)
        .map_err(|e| e.to_string())?;
    // The overlay and the Settings window both show reminders.
    let _ = app.emit("reminders-changed", ());
    Ok(reminder)
}

#[tauri::command(async)]
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

#[tauri::command(async)]
fn remove_reminder(app: AppHandle, shared: State<'_, Arc<Shared>>, id: String) -> Result<Option<reminders::Reminder>, String> {
    let removed = shared.reminders.remove(&id).map_err(|e| e.to_string())?;
    let _ = app.emit("reminders-changed", ());
    Ok(removed)
}

#[tauri::command(async)]
fn restore_reminder(app: AppHandle, shared: State<'_, Arc<Shared>>, reminder: reminders::Reminder) -> Result<(), String> {
    shared.reminders.restore(reminder).map_err(|e| e.to_string())?;
    let _ = app.emit("reminders-changed", ());
    Ok(())
}

/// The page's answer to an agent's tool call (see mcp.rs).
/// A reminder card's answer: done, snooze until a time, or skip this occurrence of a series.
#[tauri::command(async)]
fn answer_reminder(app: AppHandle, shared: State<'_, Arc<Shared>>, id: String, action: String, until: Option<u64>) -> Result<bool, String> {
    let answer = match (action.as_str(), until) {
        ("done", _) => reminders::Answer::Done,
        ("skip", _) => reminders::Answer::Skip,
        ("snooze", Some(until)) if until > journal::now_ms() => reminders::Answer::Snooze(until),
        _ => return Err("Choose a time later than now.".into()),
    };
    let answered = shared.reminders.answer(&id, answer, journal::now_ms(), &jiff::tz::TimeZone::system()).map_err(|e| e.to_string())?;
    let _ = app.emit("reminders-changed", ());
    Ok(answered)
}

/// Stores that couldn't be read at launch (store.rs), for the window's banner.
#[tauri::command(async)]
fn store_problems(shared: State<'_, Arc<Shared>>) -> Vec<store::Problem> {
    shared.problems.list()
}

/// Puts a store's last good copy back, then starts Sidefolk again so everything reads it.
#[tauri::command(async)]
fn restore_store(app: AppHandle, shared: State<'_, Arc<Shared>>, file: String) -> Result<(), String> {
    if !shared.problems.list().iter().any(|p| p.file == file && p.backup) {
        return Err("There's no last good copy of that file.".into());
    }
    let dir = shared.settings.lock().unwrap().dir.clone();
    store::restore(&dir.join(&file)).map_err(|e| e.to_string())?;
    app.restart();
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
    if !settings.hidden {
        return;
    }
    let handle = app.clone();
    let _ = app.run_on_main_thread(move || {
        let _ = overlay::set_visible(&handle, show);
    });
}

/// The user's answer from either window. Allow is refused for a request that isn't waiting or
/// couldn't be shown whole (requests.rs); the reason comes back to say so.
#[tauri::command]
fn resolve_permission(app: AppHandle, shared: State<'_, Arc<Shared>>, id: String, decision: String) -> Result<(), String> {
    let decision = match decision.as_str() {
        "allow" => Decision::Allow,
        "deny" => Decision::Deny,
        _ => Decision::Defer,
    };
    let result = shared.requests.answer(&id, decision).map_err(|refused| refused.to_string());
    if result.is_ok() {
        let _ = app.emit("permission-closed", &id);
    }
    shared.requests.changed(&app);
    result
}

/// Requests waiting on the user, for a window that just opened or reloaded.
#[tauri::command]
fn list_requests(shared: State<'_, Arc<Shared>>) -> Vec<requests::Ask> {
    shared.requests.list()
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
    // A second launch opens the running Sidefolk's window instead of starting another copy that
    // would fight it for the hook port (docs/V1.md V1-X15). Registered first, as the plugin asks.
    let builder = tauri::Builder::default().plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
        let _ = prefs::open(app);
    }));
    #[cfg(target_os = "macos")]
    let builder = builder.plugin(tauri_nspanel::init());
    builder
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .manage(claude_setup::SetupState::default())
        .manage(mcp_setup::McpSetupState::default())
        .invoke_handler(tauri::generate_handler![
            actions::allow_terminal_control,
            calendar::calendar_status,
            calendar::request_calendar,
            calendar::upcoming_events,
            prefs::problem_report,
            notes::list_notebooks,
            notes::read_notebook,
            notes::create_notebook,
            notes::add_note,
            notes::edit_note,
            notes::remove_note,
            notes::restore_note,
            notes::move_note,
            actions::open_target,
            actions::start_session,
            actions::resolve_folder,
            actions::run_command,
            actions::choose_project_folder,
            resolve_permission,
            list_requests,
            overlay_typing,
            overlay::overlay_area,
            overlay::overlay_frame,
            ui_log,
            get_settings,
            save_pet,
            get_crew,
            save_crew,
            journal_since,
            notifications::notification_status,
            notifications::request_notifications,
            list_reminders,
            add_reminder,
            update_reminder,
            remove_reminder,
            restore_reminder,
            answer_reminder,
            peek,
            mcp_reply,
            store_problems,
            restore_store,
            prefs::update_settings,
            prefs::integrations,
            prefs::tray_action,
            prefs::reveal_data_dir,
            prefs::log_error,
            prefs::pet_action,
            prefs::app_info,
            prefs::publish_status,
            prefs::get_status,
            sessions::open_session,
            sessions::terminals,
            prefs::answered,
            prefs::open_tab
        ])
        .setup(move |app| {
            let problems = store::Problems::default();
            let store = settings::Store::load(settings::data_dir(app.handle())?, &problems);
            prefs::log_panics(&store.dir);
            let shared = Arc::new(Shared {
                crew: std::sync::Mutex::new(crew::load(&store.dir, &problems)),
                status: Default::default(),
                journal: journal::Journal::open(&store.dir),
                replies: Default::default(),
                token: mcp::ensure_token(&store.dir)?,
                reminders: reminders::Reminders::load(&store.dir, &problems),
                problems,
                hook_error: Default::default(),
                notes: notes::Notes::new(&store.dir),
                settings: std::sync::Mutex::new(store),
                requests: Default::default(),
                hosts: Default::default(),
            });
            app.manage(shared.clone());
            if let Some(sender) = notifications::install(app.handle()) {
                shared.reminders.schedule_with(sender);
            }
            // Series move past occurrences that came and went, now and every 20 seconds after.
            let (handle, ticking) = (app.handle().clone(), shared.clone());
            std::thread::spawn(move || loop {
                match ticking.reminders.tick(journal::now_ms(), &jiff::tz::TimeZone::system()) {
                    Ok(true) => {
                        let _ = handle.emit("reminders-changed", ());
                    }
                    Ok(false) => {}
                    Err(error) => eprintln!("sidefolk: reminders: {error}"),
                }
                std::thread::sleep(std::time::Duration::from_secs(20));
            });
            prefs::apply_theme(app.handle(), &shared.settings.lock().unwrap().value.theme);
            app_menu::apply_dock(app.handle());
            app.set_menu(app_menu::build(app.handle())?)?;
            app.on_menu_event(|app, event| app_menu::handle(app, event.id().as_ref()));

            overlay::setup(app.handle())?;
            tray::setup(app.handle())?;
            hooks::spawn(app.handle().clone(), shared.clone());
            // First launch: the setup guide (it sets `onboarded` when finished).
            if !shared.settings.lock().unwrap().value.onboarded {
                prefs::open_at(app.handle(), "setup")?;
            }
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("Sidefolk failed to start")
        .run(|app, event| {
            // Clicking the Dock icon with no window open brings the Sidefolk window back.
            #[cfg(target_os = "macos")]
            if let tauri::RunEvent::Reopen { has_visible_windows: false, .. } = event {
                let _ = prefs::open(app);
            }
            let _ = (app, event);
        });
}
