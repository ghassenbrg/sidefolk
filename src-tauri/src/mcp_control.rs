//! Bounded, authenticated MCP capabilities. Never dispatch arbitrary tray/page commands.
//! Included by mcp.rs, so no additional main.rs module registration is needed.
use crate::{bus::Shared, notes::Notes, reminders::{Answer, Reminders}};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{io, sync::Arc};
use tauri::{AppHandle, Emitter, Manager};

pub(super) fn handles(name: &str) -> bool {
    matches!(name, "sidefolk_status" | "sidefolk_control" | "sidefolk_reminders" | "sidefolk_notes")
}

fn variant(action: &str, fields: Value, required: &[&str]) -> Value {
    let mut properties = json!({"action": {"const": action}});
    properties.as_object_mut().unwrap().extend(fields.as_object().unwrap().clone());
    let mut needed = vec!["action"];
    needed.extend(required);
    json!({"type":"object", "properties": properties, "required": needed, "additionalProperties":false})
}
fn string(max: usize) -> Value { json!({"type":"string", "minLength":1, "maxLength":max}) }
// Conservative bound within Jiff, JavaScript and native notification time ranges.
const MAX_EPOCH: u64 = 8_640_000_000_000;
fn epoch() -> Value {
    json!({"type":"integer", "minimum":1, "maximum":MAX_EPOCH, "description":"Resolved Unix epoch milliseconds, later than now. No natural-language time parsing."})
}

pub(super) fn tools() -> Vec<Value> {
    let control = [
        variant("show", json!({}), &[]), variant("hide", json!({}), &[]),
        variant("summon", json!({}), &[]), variant("open_window", json!({}), &[]),
        variant("open_settings", json!({}), &[]),
        variant("set_look", json!({"look":{"enum":["pip","spark"]}}), &["look"]),
        variant("rename", json!({"name":string(24)}), &["name"]),
        variant("set_quiet", json!({"quiet":{"type":"boolean"}}), &["quiet"]),
        variant("set_size", json!({"size":{"enum":["small","medium","large"]}}), &["size"]),
    ];
    let reminders = [
        variant("list", json!({}), &[]),
        variant("add", json!({"text":string(300), "due":epoch()}), &["text","due"]),
        variant("complete", json!({"id":string(200)}), &["id"]),
        variant("snooze", json!({"id":string(200), "until":epoch()}), &["id","until"]),
        variant("delete", json!({"id":string(200)}), &["id"]),
    ];
    let notes = [
        variant("list_notebooks", json!({}), &[]),
        variant("read", json!({"notebook":string(60)}), &[]),
        variant("append", json!({"notebook":string(60),"text":string(2000)}), &["text"]),
    ];
    vec![
        json!({"name":"sidefolk_status", "description":"Read authoritative companion preferences, native visibility and counts only. No secrets, paths, agent command input or permission answers.", "inputSchema":{"type":"object","properties":{},"additionalProperties":false}}),
        json!({"name":"sidefolk_control", "description":"Show, hide or summon the companion; open Sidefolk or Settings; persist Pip/Spark look, name, Quiet or size. No shell, permission answers or integration changes.", "inputSchema":{"type":"object","oneOf":control}}),
        json!({"name":"sidefolk_reminders", "description":"List, add, complete, snooze or delete reminders through Sidefolk's Rust engine. Times must be exact resolved epoch milliseconds. Complete handles one occurrence of a series.", "inputSchema":{"type":"object","oneOf":reminders}}),
        json!({"name":"sidefolk_notes", "description":"List notebooks, read or append a dated note. Select an exact existing notebook ID or case-insensitive full name; omitted notebook means Log. Only default Log may be created. Never guesses a near match.", "inputSchema":{"type":"object","oneOf":notes}}),
    ]
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Empty {}
#[derive(Debug, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
enum Control {
    Show {}, Hide {}, Summon {}, OpenWindow {}, OpenSettings {},
    SetLook { look: Look }, Rename { name: String },
    SetQuiet { quiet: bool }, SetSize { size: Size },
}
#[derive(Debug, Deserialize)]
#[serde(rename_all = "lowercase")]
enum Look { Pip, Spark }
#[derive(Debug, Deserialize)]
#[serde(rename_all = "lowercase")]
enum Size { Small, Medium, Large }
#[derive(Debug, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
enum ReminderCall {
    List {}, Add { text: String, due: u64 }, Complete { id: String },
    Snooze { id: String, until: u64 }, Delete { id: String },
}
#[derive(Debug, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
enum NoteCall {
    ListNotebooks {}, Read { notebook: Option<String> },
    Append { notebook: Option<String>, text: String },
}
fn parse<T: serde::de::DeserializeOwned>(args: &Value) -> Result<T, String> {
    serde_json::from_value(args.clone()).map_err(|e| format!("Invalid arguments: {e}"))
}
fn text(value: &str, max: usize) -> Result<(), String> {
    if value.trim().is_empty() || value.chars().count() > max || value.chars().any(char::is_control) {
        return Err(format!("Text must contain 1–{max} characters and no control characters."));
    }
    Ok(())
}
fn future(at: u64, now: u64) -> Result<(), String> {
    if at <= now || at > MAX_EPOCH { return Err("Choose resolved epoch milliseconds later than now and within the supported range.".into()); }
    Ok(())
}
fn saved<T>(result: io::Result<T>) -> Result<T, String> { result.map_err(|e| e.to_string()) }

// Allowlist fields instead of returning shared.status, which may contain agent commands.
fn snapshot(shared: &Shared) -> Value {
    let settings = shared.settings.lock().unwrap().value.clone();
    let crew = shared.crew.lock().unwrap();
    status(&settings, &crew, shared.reminders.list().iter().filter(|r| !r.done).count(), shared.requests.list().len())
}
fn status(settings: &crate::settings::Settings, crew: &Value, open: usize, waiting: usize) -> Value {
    let look = if crew["main"]["look"] == "spark" { "Spark" } else { "Pip" };
    json!({"companion":{"name":crew["main"]["name"].as_str().unwrap_or(look), "look":look,
        "hidden":settings.hidden,"quiet":!settings.sounds,"size":settings.pet_size},
        "reminders":{"open":open},
        "pending_requests":waiting})
}

pub(super) async fn handle(app: &AppHandle, shared: &Shared, tool: &str, args: &Value) -> Result<Value, String> {
    match tool {
        "sidefolk_status" => {
            let _: Empty = parse(args)?;
            let mut value = snapshot(shared);
            value["overlay_visible"] = on_main(app, |app| {
                Ok(json!(app.get_webview_window(crate::overlay::OVERLAY)
                    .ok_or("Companion window is unavailable")?.is_visible().map_err(|e| e.to_string())?))
            }).await?;
            Ok(value)
        }
        "sidefolk_control" => {
            let call: Control = parse(args)?;
            if let Control::Rename { name } = &call { text(name, 24)?; }
            on_main(app, move |app| control(app, call)).await
        }
        "sidefolk_reminders" => {
            let call = parse(args)?;
            let value = reminders(&shared.reminders, call, crate::journal::now_ms())?;
            if args["action"] != "list" { app.emit("reminders-changed", ()).map_err(|e| e.to_string())?; }
            Ok(value)
        }
        "sidefolk_notes" => {
            let call = parse(args)?;
            let value = notes(&shared.notes, call)?;
            if args["action"] == "append" { app.emit("notes-changed", ()).map_err(|e| e.to_string())?; }
            Ok(value)
        }
        _ => Err("Unknown Sidefolk capability".into()),
    }
}

async fn on_main(app: &AppHandle, action: impl FnOnce(&AppHandle) -> Result<Value, String> + Send + 'static) -> Result<Value, String> {
    let handle = app.clone();
    let (tx, rx) = tokio::sync::oneshot::channel();
    app.run_on_main_thread(move || { let _ = tx.send(action(&handle)); }).map_err(|e| e.to_string())?;
    rx.await.map_err(|_| "Native action did not finish".to_string())?
}

fn save_identity(dir: &std::path::Path, crew: &mut Value, problems: &crate::store::Problems, call: &Control) -> Result<(), String> {
    let mut next = if crew.is_object() { crew.clone() } else { json!({}) };
    if !next["main"].is_object() { next["main"] = json!({}); }
    match call {
        Control::Rename { name } => { text(name, 24)?; next["main"]["name"] = json!(name.trim()); }
        Control::SetLook { look } => next["main"]["look"] = json!(match look { Look::Pip => "pip", Look::Spark => "spark" }),
        _ => return Err("Unsupported identity change".into()),
    }
    saved(crate::crew::save(dir, &next, problems))?;
    *crew = next;
    Ok(())
}

fn control(app: &AppHandle, call: Control) -> Result<Value, String> {
    let shared = app.state::<Arc<Shared>>();
    // Check existence before writing a change that requires the overlay.
    let window = app.get_webview_window(crate::overlay::OVERLAY).ok_or("Companion window is unavailable")?;
    match &call {
        Control::OpenWindow {} => crate::prefs::open(app).map_err(|e| e.to_string())?,
        Control::OpenSettings {} => crate::prefs::open_at(app, "settings:general").map_err(|e| e.to_string())?,
        Control::Show {} | Control::Hide {} | Control::Summon {} => {
            let summon_x = if matches!(call, Control::Summon {}) {
                crate::overlay::fit_to_cursor_display(app).map_err(|e| e.to_string())?;
                let cursor = app.cursor_position().map_err(|e| e.to_string())?;
                let origin = window.inner_position().map_err(|e| e.to_string())?;
                Some((cursor.x - origin.x as f64) / window.scale_factor().map_err(|e| e.to_string())?)
            } else { None };
            let hidden = matches!(call, Control::Hide {});
            saved(shared.settings.lock().unwrap().update(|s| s.hidden = hidden))?;
            crate::overlay::set_visible(app, !hidden).map_err(|e| e.to_string())?;
            if let Some(x) = summon_x { window.emit("summon", json!({"x":x})).map_err(|e| e.to_string())?; }
        }
        Control::SetQuiet { quiet } => {
            saved(shared.settings.lock().unwrap().update(|s| s.sounds = !quiet))?;
        }
        Control::SetSize { size } => {
            let size = match size { Size::Small => "small", Size::Medium => "medium", Size::Large => "large" };
            saved(shared.settings.lock().unwrap().update(|s| s.pet_size = size.into()))?;
        }
        Control::Rename { .. } | Control::SetLook { .. } => {
            let dir = shared.settings.lock().unwrap().dir.clone();
            save_identity(&dir, &mut shared.crew.lock().unwrap(), &shared.problems, &call)?;
            // The page caches crew at startup. Reload only after Rust committed it; requests
            // remain in Rust and are rehydrated by the existing overlay startup lifecycle.
            window.reload().map_err(|e| e.to_string())?;
        }
    }
    let settings = shared.settings.lock().unwrap().value.clone();
    app.emit("settings-changed", &settings).map_err(|e| e.to_string())?;
    crate::tray::refresh(app).map_err(|e| e.to_string())?;
    Ok(snapshot(&shared))
}

fn reminders(engine: &Reminders, call: ReminderCall, now: u64) -> Result<Value, String> {
    let id = match &call {
        ReminderCall::Complete { id } | ReminderCall::Delete { id } | ReminderCall::Snooze { id, .. } => Some(id), _ => None,
    };
    if let Some(id) = id { text(id, 200)?; }
    match call {
        ReminderCall::List {} => Ok(json!(engine.list())),
        ReminderCall::Add { text: body, due } => {
            text(&body, 300)?; future(due, now)?;
            Ok(json!(saved(engine.add(&body, due, "", "agent", None))?))
        }
        ReminderCall::Delete { id } => Ok(json!({"deleted":saved(engine.remove(&id))?.ok_or("No such reminder")?})),
        ReminderCall::Complete { ref id } | ReminderCall::Snooze { ref id, .. } => {
            let answer = match call {
                ReminderCall::Snooze { until, .. } => { future(until, now)?; Answer::Snooze(until) }
                _ => Answer::Done,
            };
            if !saved(engine.answer(id, answer, now, &jiff::tz::TimeZone::system()))? { return Err("No open reminder with that ID".into()); }
            Ok(json!({"id":id,"reminders":engine.list()}))
        }
    }
}

fn notebook(engine: &Notes, name: Option<&str>, create_log: bool) -> Result<crate::notes::Notebook, String> {
    let name = name.unwrap_or("Log");
    text(name, 60)?;
    // Notes::find also slug-normalizes names; deliberately avoid its near-match behavior.
    let books = engine.list();
    if let Some(book) = books.iter().find(|b| b.id == name) { return Ok(book.clone()); }
    let matches: Vec<_> = books.into_iter().filter(|b| b.name.to_lowercase() == name.to_lowercase()).collect();
    match matches.len() {
        1 => Ok(matches.into_iter().next().unwrap()),
        0 if create_log && name == "Log" => saved(engine.create("Log")),
        0 => Err("No exact notebook match; use list_notebooks and choose an ID.".into()),
        _ => Err("Ambiguous notebook name; choose an exact notebook ID.".into()),
    }
}
fn notes(engine: &Notes, call: NoteCall) -> Result<Value, String> {
    match call {
        NoteCall::ListNotebooks {} => Ok(json!(engine.list())),
        NoteCall::Read { notebook: name } => {
            let book = notebook(engine, name.as_deref(), false)?;
            let page = saved(engine.read(&book.id))?;
            Ok(json!({"notebook":page.notebook,"entries":page.entries}))
        }
        NoteCall::Append { notebook: name, text: body } => {
            text(&body, 2000)?;
            let book = notebook(engine, name.as_deref(), true)?;
            let date = jiff::Zoned::now().date().to_string();
            let entry = saved(engine.add(&book.id, &body, &date, ""))?;
            Ok(json!({"notebook":book.id,"entry":entry}))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{fs, path::PathBuf, sync::atomic::{AtomicU64, Ordering}};
    struct Temp(PathBuf);
    impl Temp {
        fn new() -> Self {
            static NEXT: AtomicU64 = AtomicU64::new(0);
            let dir = std::env::temp_dir().join(format!("sidefolk-mcp-control-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
            fs::create_dir_all(&dir).unwrap();
            Self(dir)
        }
    }
    impl Drop for Temp { fn drop(&mut self) { let _ = fs::remove_dir_all(&self.0); } }

    #[test]
    fn schemas_and_dispatch_are_bounded() {
        let tools = tools();
        assert_eq!(tools.len(), 4);
        for tool in &tools {
            assert!(handles(tool["name"].as_str().unwrap()));
            assert_eq!(tool["inputSchema"]["type"], "object");
            if let Some(variants) = tool["inputSchema"]["oneOf"].as_array() {
                for variant in variants { assert_eq!(variant["additionalProperties"], false); }
            }
        }
        assert!(!handles("resolve_permission"));
        parse::<Control>(&json!({"action":"set_look","look":"spark"})).unwrap();
        let variants = tools[1]["inputSchema"]["oneOf"].as_array().unwrap();
        assert_eq!(variants.iter().find(|v| v["properties"]["action"]["const"] == "rename").unwrap()["properties"]["name"]["maxLength"], 24);
        assert_eq!(variants.iter().find(|v| v["properties"]["action"]["const"] == "set_look").unwrap()["properties"]["look"]["enum"], json!(["pip", "spark"]));
        for args in [json!({"action":"approve"}), json!({"action":"run","command":"ls"}), json!({"action":"show","command":"ls"}), json!({"action":"set_look","look":"fox"}), json!({"action":"set_quiet","quiet":"true"}), json!({"action":"set_size","size":"giant"})] {
            assert!(parse::<Control>(&args).is_err(), "{args}");
        }
        assert!(parse::<Empty>(&json!({"include_secrets":true})).is_err());
        assert!(parse::<ReminderCall>(&json!({"action":"add","text":"hi","due":"tomorrow"})).is_err());
        assert!(parse::<ReminderCall>(&json!({"action":"add","text":"hi","due":1.5})).is_err());
        assert!(parse::<NoteCall>(&json!({"action":"append","text":"x","path":"/tmp/x"})).is_err());
        for tool in &tools[1..] {
            for schema in tool["inputSchema"]["oneOf"].as_array().unwrap() {
                let mut args = json!({"action":schema["properties"]["action"]["const"]});
                for field in schema["required"].as_array().unwrap().iter().skip(1) {
                    let field = field.as_str().unwrap();
                    args[field] = match field { "look" => json!("pip"), "quiet" => json!(true), "size" => json!("medium"), "due" | "until" => json!(2_000_000_000_000_u64), _ => json!("test") };
                }
                match tool["name"].as_str().unwrap() {
                    "sidefolk_control" => { parse::<Control>(&args).unwrap(); }
                    "sidefolk_reminders" => { parse::<ReminderCall>(&args).unwrap(); }
                    _ => { parse::<NoteCall>(&args).unwrap(); }
                }
            }
        }
    }

    #[test]
    fn exact_times_and_reminder_lifecycle_survive_reload() {
        let dir = Temp::new();
        let engine = Reminders::load(&dir.0, &Default::default());
        let now = crate::journal::now_ms();
        for due in [0, now, now - 1, MAX_EPOCH + 1] {
            assert!(reminders(&engine, ReminderCall::Add { text:"test".into(), due }, now).is_err());
        }
        assert!(engine.list().is_empty());
        let due = now + 86_400_000;
        let value = reminders(&engine, ReminderCall::Add { text:"test".into(), due }, now).unwrap();
        let id = value["id"].as_str().unwrap().to_string();
        assert_eq!(value["due"], due);
        reminders(&engine, ReminderCall::Snooze { id:id.clone(), until:due + 1000 }, now).unwrap();
        let loaded = Reminders::load(&dir.0, &Default::default());
        let r = &loaded.list()[0];
        assert_eq!((r.anchor, r.occurrence, r.due), (due, due, due + 1000));
        reminders(&engine, ReminderCall::Complete { id:id.clone() }, now).unwrap();
        assert!(Reminders::load(&dir.0, &Default::default()).list()[0].done);
        assert!(reminders(&engine, ReminderCall::Complete { id:id.clone() }, now).is_err());
        reminders(&engine, ReminderCall::Delete { id:id.clone() }, now).unwrap();
        assert!(Reminders::load(&dir.0, &Default::default()).list().is_empty());
        assert!(reminders(&engine, ReminderCall::Delete { id }, now).is_err());
    }

    #[test]
    fn series_completion_and_snooze_keep_the_anchor() {
        let dir = Temp::new();
        let engine = Reminders::load(&dir.0, &Default::default());
        let now = crate::journal::now_ms();
        let due = now + 86_400_000;
        let r = engine.add("weekly", due, "", "agent", Some(crate::reminders::Repeat { every:"week".into(), n:1, days:vec![] })).unwrap();
        reminders(&engine, ReminderCall::Snooze { id:r.id.clone(), until:due + 1000 }, now).unwrap();
        reminders(&engine, ReminderCall::Complete { id:r.id }, now).unwrap();
        let r = &engine.list()[0];
        assert_eq!(r.anchor, due);
        assert!(!r.done);
        assert!(r.due > due + 1000);
        assert_eq!(r.due, r.occurrence);
    }

    #[test]
    fn status_exposes_only_the_allowlist() {
        let settings = crate::settings::Settings::default();
        let crew = json!({"main":{"name":"Pip","look":"pip","token":"SECRET"},"command":"SECRET"});
        let value = status(&settings, &crew, 2, 3);
        assert!(!value.to_string().contains("SECRET"));
        assert_eq!(value["companion"].as_object().unwrap().len(), 5);
        assert_eq!(value["reminders"]["open"], 2);
        assert_eq!(value["pending_requests"], 3);
        assert!(value.get("settings").is_none());
    }

    #[test]
    fn notes_use_exact_destination_or_default_log() {
        let dir = Temp::new();
        let engine = Notes::new(&dir.0);
        let book = engine.create("Evaluation H2 2026").unwrap();
        for name in ["Evaluation", "Evaluation H2 2026!", "../evaluation-h2-2026"] {
            assert!(notes(&engine, NoteCall::Append { notebook:Some(name.into()), text:"kept draft".into() }).is_err());
        }
        notes(&engine, NoteCall::Append { notebook:Some("EVALUATION H2 2026".into()), text:"shipped".into() }).unwrap();
        notes(&engine, NoteCall::Append { notebook:None, text:"default".into() }).unwrap();
        let loaded = Notes::new(&dir.0);
        assert_eq!(loaded.read(&book.id).unwrap().entries[0].text, "shipped");
        assert_eq!(loaded.read("log").unwrap().entries[0].text, "default");
        let read = notes(&loaded, NoteCall::Read { notebook:None }).unwrap();
        assert!(read.get("path").is_none());
        assert!(notes(&engine, NoteCall::Append { notebook:None, text:" ".into() }).is_err());
        assert!(notes(&engine, NoteCall::Append { notebook:None, text:"x".repeat(2001) }).is_err());
    }

    #[test]
    fn failed_writes_do_not_replace_memory_or_report_success() {
        let dir = Temp::new();
        let problems = crate::store::Problems::default();
        let mut crew = json!({"main":{"name":"Original"},"extra":42});
        let original = crew.clone();
        assert!(save_identity(&dir.0, &mut crew, &problems, &Control::Rename { name:"x".repeat(25) }).is_err());
        assert_eq!(crew, original);
        save_identity(&dir.0, &mut crew, &problems, &Control::Rename { name:"x".repeat(24) }).unwrap();
        save_identity(&dir.0, &mut crew, &problems, &Control::Rename { name:"New".into() }).unwrap();
        assert_eq!(crate::crew::load(&dir.0, &problems), crew);
        save_identity(&dir.0, &mut crew, &problems, &Control::SetLook { look:Look::Spark }).unwrap();
        assert_eq!(crate::crew::load(&dir.0, &problems)["main"]["look"], "spark");
        assert_eq!(crew["extra"], 42);
        let engine = Reminders::load(&dir.0, &problems);
        let notes_engine = Notes::new(&dir.0);
        notes_engine.create("Log").unwrap();
        let prior = crew.clone();
        // A file where a directory was expected produces a deterministic IO failure, even as root.
        fs::remove_dir_all(&dir.0).unwrap();
        fs::write(&dir.0, "blocked").unwrap();
        assert!(save_identity(&dir.0, &mut crew, &problems, &Control::Rename { name:"Lost".into() }).is_err());
        assert_eq!(crew, prior);
        let now = crate::journal::now_ms();
        assert!(reminders(&engine, ReminderCall::Add { text:"x".into(), due:now + 10000 }, now).is_err());
        assert!(engine.list().is_empty());
        assert!(notes(&notes_engine, NoteCall::Append { notebook:None, text:"lost".into() }).is_err());
        fs::remove_file(&dir.0).unwrap();
    }
}
