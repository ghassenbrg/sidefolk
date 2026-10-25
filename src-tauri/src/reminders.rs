//! Reminders set from the command bar (and, through MCP, by agents), stored in
//! reminders.json. The page decides when to show them; this module only keeps the list.
use serde::{Deserialize, Serialize};
use std::{
    io,
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
    /// Comes back after it's done (the companion moves `due` to the next time; src/when.ts).
    pub repeat: Option<Repeat>,
    pub history: Vec<History>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct History {
    pub at: u64,
    pub action: String,
    pub due: u64,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Repeat {
    /// "day", "weekday", "week" or "month".
    pub every: String,
    pub n: u32,
}

impl Repeat {
    pub fn valid(&self) -> bool {
        matches!(self.every.as_str(), "day" | "weekday" | "week" | "month") && (1..=52).contains(&self.n)
    }
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
            repeat: None,
            history: Vec::new(),
        }
    }
}

#[derive(Deserialize, Default)]
pub struct Change {
    pub text: Option<String>,
    pub done: Option<bool>,
    pub due: Option<u64>,
    pub fired: Option<bool>,
    pub repeat: Option<Repeat>,
    #[serde(default)]
    pub clear_repeat: bool,
    #[serde(default)]
    pub completed: bool,
}

pub struct Reminders {
    path: PathBuf,
    /// The file couldn't be read or set aside, so nothing may be written over it (store.rs).
    blocked: bool,
    list: Mutex<Vec<Reminder>>,
    notifications: Mutex<Option<std::sync::mpsc::Sender<Vec<Reminder>>>>,
}

impl Reminders {
    /// A damaged file is set aside and reported, never read as an empty list that the next save
    /// would write over (docs/V1.md V1-S2).
    pub fn load(data_dir: &std::path::Path, problems: &crate::store::Problems) -> Self {
        let path = data_dir.join("reminders.json");
        let now = now_ms();
        let loaded = crate::store::load::<Vec<Reminder>>(&path, 1, serde_json::Value::is_array, |_, data| data);
        problems.note(&path, &loaded);
        let blocked = matches!(loaded, crate::store::Loaded::Corrupt { kept: None, .. });
        let list = loaded
            .or_default()
            .into_iter()
            .filter(|r| !r.done || now.saturating_sub(r.due) < KEEP_DONE_MS)
            .collect();
        Self {
            path,
            blocked,
            list: Mutex::new(list),
            notifications: Mutex::new(None),
        }
    }

    pub fn schedule_with(&self, sender: std::sync::mpsc::Sender<Vec<Reminder>>) {
        let list = self.list.lock().unwrap();
        let _ = sender.send(list.clone());
        *self.notifications.lock().unwrap() = Some(sender);
    }

    pub fn reschedule(&self) {
        let list = self.list.lock().unwrap();
        self.schedule(&list);
    }

    fn schedule(&self, list: &[Reminder]) {
        if let Some(sender) = self.notifications.lock().unwrap().as_ref() {
            let _ = sender.send(list.to_vec());
        }
    }

    pub fn list(&self) -> Vec<Reminder> {
        self.list.lock().unwrap().clone()
    }

    pub fn add(&self, text: &str, due: u64, project: &str, from: &str, repeat: Option<Repeat>) -> io::Result<Reminder> {
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
            repeat: repeat.filter(Repeat::valid),
            history: vec![History { at: now, action: "Created".into(), due }],
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
        let old_due = r.due;
        if let Some(text) = &change.text {
            let text: String = text.split_whitespace().collect::<Vec<_>>().join(" ");
            if text.is_empty() {
                return Err(io::Error::other("A reminder needs some text"));
            }
            r.text = text.chars().take(MAX_TEXT).collect();
        }
        if change.repeat.as_ref().is_some_and(|repeat| !repeat.valid()) {
            return Err(io::Error::other("Choose a valid repeat interval (1–52)"));
        }
        if change.clear_repeat { r.repeat = None; }
        else if let Some(repeat) = &change.repeat { r.repeat = Some(repeat.clone()); }
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
        let action = if change.completed || change.done == Some(true) { Some("Completed") }
            else if change.text.is_some() || change.repeat.is_some() || change.clear_repeat { Some("Edited") }
            else if change.due.is_some() { Some("Rescheduled") } else { None };
        if let Some(action) = action {
            r.history.push(History { at: now_ms(), action: action.into(), due: if action == "Completed" { old_due } else { r.due } });
            if r.history.len() > 50 { r.history.drain(..r.history.len() - 50); }
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
        if self.blocked {
            return Err(io::Error::other("Your reminders file couldn't be read, so I won't write over it."));
        }
        crate::store::save(&self.path, 1, &list)?;
        self.schedule(list);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    #[test]
    fn every_saved_mutation_updates_the_notification_schedule() {
        let dir = std::env::temp_dir().join(format!("sidefolk-notification-store-{}", std::process::id()));
        let store = Reminders::load(&dir, &Default::default());
        let (tx, rx) = std::sync::mpsc::channel();
        store.schedule_with(tx);
        assert!(rx.recv().unwrap().is_empty());
        let r = store.add("alarm", now_ms() + 60_000, "", "you", None).unwrap();
        assert_eq!(rx.recv().unwrap(), vec![r.clone()]);
        store.update(&r.id, &Change { due: Some(r.due + 60_000), ..Default::default() }).unwrap();
        assert_eq!(rx.recv().unwrap()[0].due, r.due + 60_000);
        let removed = store.remove(&r.id).unwrap().unwrap();
        assert!(rx.recv().unwrap().is_empty());
        store.restore(removed.clone()).unwrap();
        assert_eq!(rx.recv().unwrap(), vec![removed]);
        store.update(&r.id, &Change { done: Some(true), ..Default::default() }).unwrap();
        let completed = rx.recv().unwrap().remove(0);
        assert!(completed.done);
        assert_eq!(completed.history.last().unwrap().action, "Completed");
        assert_eq!(completed.history.last().unwrap().due, r.due + 60_000);
        assert!(store.add("", 0, "", "you", None).is_err());
        assert!(rx.try_recv().is_err());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn add_update_and_reload() {
        let dir = std::env::temp_dir().join(format!("sidefolk-reminders-{}", std::process::id()));
        let store = Reminders::load(&dir, &Default::default());
        assert!(store.add("   ", 1, "", "you", None).is_err());
        let r = store.add("review  the PR", now_ms() + 60_000, "/p", "claude", None).unwrap();
        assert_eq!(r.text, "review the PR");
        assert!(store.update(&r.id, &Change { fired: Some(true), ..Default::default() }).unwrap());
        assert!(store.update(&r.id, &Change { due: Some(5), ..Default::default() }).unwrap());
        let reloaded = Reminders::load(&dir, &Default::default()).list();
        assert_eq!(reloaded.len(), 1);
        assert_eq!((reloaded[0].due, reloaded[0].fired), (5, false));
        // Done long ago: dropped on the next load.
        store.update(&r.id, &Change { done: Some(true), ..Default::default() }).unwrap();
        assert!(Reminders::load(&dir, &Default::default()).list().is_empty());
        assert!(!store.update("missing", &Change::default()).unwrap());
        let weekly = Repeat { every: "week".into(), n: 2 };
        let r = store.add("send the report", now_ms() + 60_000, "", "you", Some(weekly.clone())).unwrap();
        assert_eq!(r.repeat, Some(weekly.clone()));
        store.update(&r.id, &serde_json::from_str::<Change>(r#"{"text":"new title"}"#).unwrap()).unwrap();
        assert_eq!(store.list().iter().find(|x| x.id == r.id).unwrap().repeat, Some(weekly));
        store.update(&r.id, &serde_json::from_str::<Change>(r#"{"repeat":{"every":"day","n":3}}"#).unwrap()).unwrap();
        assert_eq!(store.list().iter().find(|x| x.id == r.id).unwrap().repeat.as_ref().unwrap().n, 3);
        assert!(store.update(&r.id, &serde_json::from_str::<Change>(r#"{"repeat":{"every":"day","n":0}}"#).unwrap()).is_err());
        store.update(&r.id, &serde_json::from_str::<Change>(r#"{"clear_repeat":true}"#).unwrap()).unwrap();
        assert_eq!(Reminders::load(&dir, &Default::default()).list().iter().find(|x| x.id == r.id).unwrap().repeat, None);
        let odd = store.add("odd", now_ms() + 60_000, "", "you", Some(Repeat { every: "hour".into(), n: 1 })).unwrap();
        assert_eq!(odd.repeat, None);
        let r = store.add("call the bank", now_ms() + 60_000, "", "you", None).unwrap();
        assert!(store.update(&r.id, &Change { text: Some(" ".into()), ..Default::default() }).is_err());
        store.update(&r.id, &Change { text: Some("call  mum".into()), ..Default::default() }).unwrap();
        let removed = store.remove(&r.id).unwrap().unwrap();
        assert_eq!(removed.text, "call mum");
        assert!(store.list().iter().all(|x| x.id != r.id));
        store.restore(removed).unwrap();
        assert!(Reminders::load(&dir, &Default::default()).list().iter().any(|x| x.id == r.id));
        fs::remove_dir_all(dir).unwrap();
    }
}
