//! Notebooks: one Markdown file per notebook in <data>/notes, readable and editable anywhere.
//! A notebook is a `# Name` heading and dated entries (`- 2026-10-24 — text _(project)_`).
//! Lines the app didn't write (the user's own edits) are kept as they are.
use std::{
    fs, io,
    path::{Path, PathBuf},
    sync::Mutex,
};

use serde::Serialize;

const MAX_TEXT: usize = 2000;
const MAX_NAME: usize = 60;

#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Entry {
    /// Line number in the file; edits check the text is still there before changing it.
    pub line: usize,
    pub date: String,
    pub text: String,
    pub project: String,
}

#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Notebook {
    pub id: String,
    pub name: String,
    pub count: usize,
    /// Unix ms of the last change.
    pub updated: u64,
}

#[derive(Serialize, Debug)]
pub struct Page {
    #[serde(flatten)]
    pub notebook: Notebook,
    pub entries: Vec<Entry>,
    pub path: String,
}

pub struct Notes {
    dir: PathBuf,
    write: Mutex<()>,
}

fn clean(text: &str, max: usize) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ").chars().take(max).collect()
}

fn slug(name: &str) -> String {
    let mut out = String::new();
    for c in name.to_lowercase().chars() {
        if c.is_alphanumeric() {
            out.push(c);
        } else if !out.ends_with('-') {
            out.push('-');
        }
    }
    let out: String = out.trim_matches('-').chars().take(MAX_NAME).collect();
    if out.is_empty() { "notes".into() } else { out }
}

fn is_date(s: &str) -> bool {
    s.len() == 10 && s.chars().enumerate().all(|(i, c)| if i == 4 || i == 7 { c == '-' } else { c.is_ascii_digit() })
}

fn parse_entry(line: usize, text: &str) -> Option<Entry> {
    let rest = text.strip_prefix("- ")?;
    let date = rest.get(..10).filter(|d| is_date(d))?;
    let body = rest[10..].strip_prefix(" — ")?;
    let (text, project) = match body.rsplit_once(" _(") {
        Some((text, project)) if project.ends_with(")_") => (text, &project[..project.len() - 2]),
        _ => (body, ""),
    };
    Some(Entry { line, date: date.into(), text: text.into(), project: project.into() })
}

fn entry_line(date: &str, text: &str, project: &str) -> String {
    if project.is_empty() { format!("- {date} — {text}") } else { format!("- {date} — {text} _({project})_") }
}

fn modified(path: &Path) -> u64 {
    fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map_or(0, |d| d.as_millis() as u64)
}

impl Notes {
    pub fn new(data_dir: &Path) -> Self {
        Self { dir: data_dir.join("notes"), write: Mutex::new(()) }
    }

    fn path(&self, id: &str) -> io::Result<PathBuf> {
        if id.is_empty() || slug(id) != id {
            return Err(io::Error::other("No such notebook"));
        }
        Ok(self.dir.join(format!("{id}.md")))
    }

    fn lines(&self, id: &str) -> io::Result<Vec<String>> {
        Ok(fs::read_to_string(self.path(id)?)?.lines().map(String::from).collect())
    }

    fn save(&self, id: &str, lines: &[String]) -> io::Result<()> {
        crate::settings::atomic_write(&self.path(id)?, format!("{}\n", lines.join("\n")).as_bytes())
    }

    fn info(&self, id: &str, lines: &[String]) -> io::Result<Notebook> {
        let name = lines.iter().find_map(|l| l.strip_prefix("# ")).unwrap_or(id).trim().to_string();
        let count = lines.iter().enumerate().filter(|(i, l)| parse_entry(*i, l).is_some()).count();
        Ok(Notebook { id: id.into(), name, count, updated: modified(&self.path(id)?) })
    }

    pub fn list(&self) -> Vec<Notebook> {
        let Ok(dir) = fs::read_dir(&self.dir) else { return vec![] };
        let mut books: Vec<Notebook> = dir
            .flatten()
            .filter_map(|e| e.file_name().to_str()?.strip_suffix(".md").map(String::from))
            .filter_map(|id| self.lines(&id).and_then(|lines| self.info(&id, &lines)).ok())
            .collect();
        books.sort_by_key(|book| std::cmp::Reverse(book.updated));
        books
    }

    pub fn read(&self, id: &str) -> io::Result<Page> {
        let lines = self.lines(id)?;
        let entries = lines.iter().enumerate().filter_map(|(i, l)| parse_entry(i, l)).collect();
        Ok(Page { notebook: self.info(id, &lines)?, entries, path: self.path(id)?.to_string_lossy().into() })
    }

    /// A notebook by its id or name (any case); `create` makes it when there is none.
    pub fn find(&self, name: &str) -> Option<Notebook> {
        let want = name.trim().to_lowercase();
        self.list().into_iter().find(|b| b.id == slug(&want) || b.name.to_lowercase() == want)
    }

    pub fn create(&self, name: &str) -> io::Result<Notebook> {
        let name = clean(name, MAX_NAME);
        if name.is_empty() {
            return Err(io::Error::other("A notebook needs a name"));
        }
        if let Some(existing) = self.find(&name) {
            return Ok(existing);
        }
        let _guard = self.write.lock().unwrap();
        fs::create_dir_all(&self.dir)?;
        let base = slug(&name);
        let id = (1..).map(|n| if n == 1 { base.clone() } else { format!("{base}-{n}") }).find(|id| !self.dir.join(format!("{id}.md")).exists()).unwrap();
        let lines = vec![format!("# {name}"), String::new()];
        self.save(&id, &lines)?;
        self.info(&id, &lines)
    }

    pub fn add(&self, id: &str, text: &str, date: &str, project: &str) -> io::Result<Entry> {
        let text = clean(text, MAX_TEXT);
        if text.is_empty() || !is_date(date) {
            return Err(io::Error::other("A note needs some text"));
        }
        let _guard = self.write.lock().unwrap();
        let mut lines = self.lines(id)?;
        let line = entry_line(date, &text, &clean(project, MAX_NAME));
        lines.push(line.clone());
        self.save(id, &lines)?;
        Ok(parse_entry(lines.len() - 1, &line).unwrap())
    }

    /// Changes an entry's text, if that line still holds what the window showed.
    pub fn edit(&self, id: &str, at: &Entry, text: &str) -> io::Result<Entry> {
        let text = clean(text, MAX_TEXT);
        if text.is_empty() {
            return Err(io::Error::other("A note needs some text"));
        }
        let _guard = self.write.lock().unwrap();
        let mut lines = self.lines(id)?;
        let current = lines.get(at.line).and_then(|l| parse_entry(at.line, l));
        if current.as_ref() != Some(at) {
            return Err(io::Error::other("This notebook changed on disk. Reopen it and try again."));
        }
        lines[at.line] = entry_line(&at.date, &text, &at.project);
        self.save(id, &lines)?;
        Ok(parse_entry(at.line, &lines[at.line]).unwrap())
    }

    pub fn remove(&self, id: &str, at: &Entry) -> io::Result<()> {
        let _guard = self.write.lock().unwrap();
        let mut lines = self.lines(id)?;
        if lines.get(at.line).and_then(|l| parse_entry(at.line, l)).as_ref() != Some(at) {
            return Err(io::Error::other("This notebook changed on disk. Reopen it and try again."));
        }
        lines.remove(at.line);
        self.save(id, &lines)
    }

    /// Moves an entry to another notebook with its date and project. It's written there before it
    /// leaves here, so a failure never loses it.
    pub fn move_entry(&self, from: &str, at: &Entry, to: &str) -> io::Result<Entry> {
        if from == to {
            return Err(io::Error::other("It's already in that notebook."));
        }
        if self.lines(from)?.get(at.line).and_then(|l| parse_entry(at.line, l)).as_ref() != Some(at) {
            return Err(io::Error::other("This notebook changed on disk. Reopen it and try again."));
        }
        let moved = self.add(to, &at.text, &at.date, &at.project)?;
        self.remove(from, at)?;
        Ok(moved)
    }

    /// Puts a removed entry back where it was (Undo).
    pub fn restore(&self, id: &str, entry: &Entry) -> io::Result<()> {
        let _guard = self.write.lock().unwrap();
        let mut lines = self.lines(id)?;
        let at = entry.line.min(lines.len());
        lines.insert(at, entry_line(&entry.date, &clean(&entry.text, MAX_TEXT), &entry.project));
        self.save(id, &lines)
    }
}

// Commands for the window and the companion, off the main thread (they read and write files).
// Every change emits "notes-changed" to both.

type Shared<'a> = tauri::State<'a, std::sync::Arc<crate::bus::Shared>>;

fn changed<T>(app: &tauri::AppHandle, result: io::Result<T>) -> Result<T, String> {
    use tauri::Emitter;
    let value = result.map_err(|e| e.to_string())?;
    let _ = app.emit("notes-changed", ());
    Ok(value)
}

#[tauri::command(async)]
pub fn list_notebooks(shared: Shared<'_>) -> Vec<Notebook> {
    shared.notes.list()
}

#[tauri::command(async)]
pub fn read_notebook(shared: Shared<'_>, id: String) -> Result<Page, String> {
    shared.notes.read(&id).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn create_notebook(app: tauri::AppHandle, shared: Shared<'_>, name: String) -> Result<Notebook, String> {
    changed(&app, shared.notes.create(&name))
}

/// Adds a note to a notebook by id or name, creating it when `create` is set ("new notebook").
#[tauri::command(async)]
pub fn add_note(app: tauri::AppHandle, shared: Shared<'_>, notebook: String, text: String, date: String, project: Option<String>, create: Option<bool>) -> Result<(Notebook, Entry), String> {
    let book = match shared.notes.find(&notebook) {
        Some(book) => book,
        None if create == Some(true) => shared.notes.create(&notebook).map_err(|e| e.to_string())?,
        None => return Err(format!("There's no notebook called {notebook}.")),
    };
    let entry = changed(&app, shared.notes.add(&book.id, &text, &date, project.as_deref().unwrap_or_default()))?;
    Ok((book, entry))
}

#[tauri::command(async)]
pub fn edit_note(app: tauri::AppHandle, shared: Shared<'_>, id: String, entry: EntryRef, text: String) -> Result<Entry, String> {
    changed(&app, shared.notes.edit(&id, &entry.into(), &text))
}

#[tauri::command(async)]
pub fn remove_note(app: tauri::AppHandle, shared: Shared<'_>, id: String, entry: EntryRef) -> Result<(), String> {
    changed(&app, shared.notes.remove(&id, &entry.into()))
}

#[tauri::command(async)]
pub fn move_note(app: tauri::AppHandle, shared: Shared<'_>, id: String, entry: EntryRef, to: String) -> Result<(Notebook, Entry), String> {
    let book = shared.notes.find(&to).ok_or_else(|| format!("There's no notebook called {to}."))?;
    let entry = changed(&app, shared.notes.move_entry(&id, &entry.into(), &book.id))?;
    Ok((book, entry))
}

#[tauri::command(async)]
pub fn restore_note(app: tauri::AppHandle, shared: Shared<'_>, id: String, entry: EntryRef) -> Result<(), String> {
    changed(&app, shared.notes.restore(&id, &entry.into()))
}

/// An entry as the window sent it back.
#[derive(serde::Deserialize)]
pub struct EntryRef {
    line: usize,
    date: String,
    text: String,
    project: String,
}

impl From<EntryRef> for Entry {
    fn from(e: EntryRef) -> Self {
        Entry { line: e.line, date: e.date, text: e.text, project: e.project }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn moves_an_entry_with_its_date_and_project() {
        let dir = std::env::temp_dir().join(format!("sidefolk-notes-move-{}", std::process::id()));
        let notes = Notes::new(&dir);
        let log = notes.create("Log").unwrap();
        let evaluation = notes.create("Evaluation H2 2026").unwrap();
        let entry = notes.add(&log.id, "shipped the login migration", "2026-10-03", "api").unwrap();
        let moved = notes.move_entry(&log.id, &entry, &evaluation.id).unwrap();
        assert_eq!((moved.date.as_str(), moved.text.as_str(), moved.project.as_str()), ("2026-10-03", "shipped the login migration", "api"));
        assert!(notes.read(&log.id).unwrap().entries.is_empty());
        // A line that changed on disk isn't moved (and nothing is lost).
        let stale = Entry { text: "something else".into(), ..moved.clone() };
        assert!(notes.move_entry(&evaluation.id, &stale, &log.id).is_err());
        assert_eq!(notes.read(&evaluation.id).unwrap().entries.len(), 1);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn notebooks_are_markdown_that_survives_hand_edits() {
        let dir = std::env::temp_dir().join(format!("sidefolk-notes-{}", std::process::id()));
        let notes = Notes::new(&dir);
        assert!(notes.list().is_empty());
        let book = notes.create("Evaluation H2 2026").unwrap();
        assert_eq!((book.id.as_str(), book.name.as_str()), ("evaluation-h2-2026", "Evaluation H2 2026"));
        assert_eq!(notes.create("evaluation h2 2026").unwrap().id, book.id);
        notes.add(&book.id, "shipped the  login migration", "2026-10-24", "sidefolk").unwrap();
        notes.add(&book.id, "mentored Sam", "2026-10-25", "").unwrap();
        let text = fs::read_to_string(dir.join("notes/evaluation-h2-2026.md")).unwrap();
        assert_eq!(text, "# Evaluation H2 2026\n\n- 2026-10-24 — shipped the login migration _(sidefolk)_\n- 2026-10-25 — mentored Sam\n");

        // A line the user wrote by hand stays; entries keep working around it.
        fs::write(dir.join("notes/evaluation-h2-2026.md"), format!("{text}Some thoughts of my own.\n")).unwrap();
        let page = notes.read(&book.id).unwrap();
        assert_eq!(page.entries.len(), 2);
        assert_eq!(page.entries[0].project, "sidefolk");
        let edited = notes.edit(&book.id, &page.entries[0], "shipped the login migration, errors down 40%").unwrap();
        assert!(notes.edit(&book.id, &page.entries[0], "stale").is_err());
        notes.remove(&book.id, &edited).unwrap();
        notes.restore(&book.id, &edited).unwrap();
        let text = fs::read_to_string(dir.join("notes/evaluation-h2-2026.md")).unwrap();
        assert!(text.contains("errors down 40% _(sidefolk)_") && text.ends_with("Some thoughts of my own.\n"));
        assert_eq!(notes.find("EVALUATION H2 2026").unwrap().count, 2);
        assert!(notes.read("../secrets").is_err());
        assert!(notes.add(&book.id, "x", "yesterday", "").is_err());
        fs::remove_dir_all(dir).unwrap();
    }
}
