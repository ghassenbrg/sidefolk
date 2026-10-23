//! Reminders set from the command bar (and, through MCP, by agents), stored in
//! reminders.json. The page decides when to show them; this module only keeps the list.
use serde::{Deserialize, Serialize};
use std::{
    fs, io,
    path::PathBuf,
    sync::{
        Mutex,
        atomic::{AtomicU64, Ordering},
    },
};

use crate::journal::now_ms;

/// Finished reminders are kept this long, then dropped on load.
const KEEP_DONE_MS: u64 = 7 * 86_400_000;
const MAX_TEXT: usize = 300;
const MAX_OPEN: usize = 500;

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase", default)]
pub struct Reminder {
    pub id: String,
    pub text: String,
    /// Unix milliseconds.
    pub due: u64,
    /// Project folder whose pet delivers it; empty for the main pet.
    pub project: String,
    /// Who set it: "you", or the agent that asked.
    pub from: String,
    pub created: u64,
    pub done: bool,
    /// Shown at least once (it may be showing now, or snoozed later).
    pub fired: bool,
}

impl Default for Reminder {
    fn default() -> Self {
        Self {
            id: String::new(),
            text: String::new(),
            due: 0,
            project: String::new(),
            from: "you".into(),
            created: 0,
            done: false,
            fired: false,
        }
    }
}

#[derive(Deserialize, Default)]
pub struct Change {
    pub text: Option<String>,
    pub done: Option<bool>,
    pub due: Option<u64>,
    pub fired: Option<bool>,
}

pub struct Reminders {
    path: PathBuf,
    list: Mutex<Vec<Reminder>>,
}

impl Reminders {
    pub fn load(data_dir: &std::path::Path) -> Self {
        let path = data_dir.join("reminders.json");
        let now = now_ms();
        let list: Vec<Reminder> = fs::read(&path)
            .ok()
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default();
        let list = list
            .into_iter()
            .filter(|r| !r.done || now.saturating_sub(r.due) < KEEP_DONE_MS)
            .collect();
        Self {
            path,
            list: Mutex::new(list),
        }
    }

    pub fn list(&self) -> Vec<Reminder> {
        self.list.lock().unwrap().clone()
    }

    pub fn add(&self, text: &str, due: u64, project: &str, from: &str) -> io::Result<Reminder> {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let text: String = text.split_whitespace().collect::<Vec<_>>().join(" ");
        if text.is_empty() {
            return Err(io::Error::other("A reminder needs some text"));
        }
        let mut list = self.list.lock().unwrap();
        if list.iter().filter(|r| !r.done).count() >= MAX_OPEN {
            return Err(io::Error::other("Too many open reminders"));
        }
        let now = now_ms();
        let reminder = Reminder {
            id: format!("r{now}-{}", NEXT.fetch_add(1, Ordering::Relaxed)),
            text: text.chars().take(MAX_TEXT).collect(),
            due,
            project: project.to_string(),
            from: from.to_string(),
            created: now,
            ..Default::default()
        };
        let mut next = list.clone();
        next.push(reminder.clone());
        self.write(&next)?;
        *list = next;
        Ok(reminder)
    }

    pub fn update(&self, id: &str, change: &Change) -> io::Result<bool> {
        let mut list = self.list.lock().unwrap();
        let mut next = list.clone();
        let Some(r) = next.iter_mut().find(|r| r.id == id) else {
            return Ok(false);
        };
        if let Some(text) = &change.text {
            let text: String = text.split_whitespace().collect::<Vec<_>>().join(" ");
            if text.is_empty() {
                return Err(io::Error::other("A reminder needs some text"));
            }
            r.text = text.chars().take(MAX_TEXT).collect();
        }
        if let Some(done) = change.done {
            r.done = done;
        }
        if let Some(due) = change.due {
            r.due = due;
            r.fired = false;
        }
        if let Some(fired) = change.fired {
            r.fired = fired;
        }
        self.write(&next)?;
        *list = next;
        Ok(true)
    }

    /// Deletes a reminder and returns it, so the dashboard can offer Undo.
    pub fn remove(&self, id: &str) -> io::Result<Option<Reminder>> {
        let mut list = self.list.lock().unwrap();
        let Some(index) = list.iter().position(|r| r.id == id) else {
            return Ok(None);
        };
        let mut next = list.clone();
        let removed = next.remove(index);
        self.write(&next)?;
        *list = next;
        Ok(Some(removed))
    }

    /// Puts back a reminder that `remove` returned (Undo).
    pub fn restore(&self, reminder: Reminder) -> io::Result<()> {
        let mut list = self.list.lock().unwrap();
        if list.iter().any(|r| r.id == reminder.id) || reminder.text.trim().is_empty() {
            return Ok(());
        }
        let mut next = list.clone();
        next.push(Reminder { text: reminder.text.chars().take(MAX_TEXT).collect(), ..reminder });
        self.write(&next)?;
        *list = next;
        Ok(())
    }

    fn write(&self, list: &[Reminder]) -> io::Result<()> {
        crate::settings::atomic_write(&self.path, &serde_json::to_vec_pretty(list)?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn add_update_and_reload() {
        let dir = std::env::temp_dir().join(format!("sidefolk-reminders-{}", std::process::id()));
        let store = Reminders::load(&dir);
        assert!(store.add("   ", 1, "", "you").is_err());
        let r = store.add("review  the PR", now_ms() + 60_000, "/p", "claude").unwrap();
        assert_eq!(r.text, "review the PR");
        assert!(store.update(&r.id, &Change { fired: Some(true), ..Default::default() }).unwrap());
        assert!(store.update(&r.id, &Change { due: Some(5), ..Default::default() }).unwrap());
        let reloaded = Reminders::load(&dir).list();
        assert_eq!(reloaded.len(), 1);
        assert_eq!((reloaded[0].due, reloaded[0].fired), (5, false));
        // Done long ago: dropped on the next load.
        store.update(&r.id, &Change { done: Some(true), ..Default::default() }).unwrap();
        assert!(Reminders::load(&dir).list().is_empty());
        assert!(!store.update("missing", &Change::default()).unwrap());
        let r = store.add("call the bank", now_ms() + 60_000, "", "you").unwrap();
        assert!(store.update(&r.id, &Change { text: Some(" ".into()), ..Default::default() }).is_err());
        store.update(&r.id, &Change { text: Some("call  mum".into()), ..Default::default() }).unwrap();
        let removed = store.remove(&r.id).unwrap().unwrap();
        assert_eq!(removed.text, "call mum");
        assert!(store.list().iter().all(|x| x.id != r.id));
        store.restore(removed).unwrap();
        assert!(Reminders::load(&dir).list().iter().any(|x| x.id == r.id));
        fs::remove_dir_all(dir).unwrap();
    }
}
