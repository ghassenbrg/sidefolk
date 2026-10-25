//! Reminders set from Quick add (and, through MCP, by agents), stored in reminders.json. This
//! module owns their schedule (docs/V1.md §4): a repeating reminder is a series with a fixed
//! anchor, every occurrence fires whether or not the last one was handled, Done and Skip move to
//! the next occurrence, and a snooze moves only the current one. The page shows them.
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

/// How a reminder card was answered.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Answer {
    Done,
    /// Show it again then; the series doesn't move.
    Snooze(u64),
    /// Skip this occurrence of a series.
    Skip,
}

/// At most this many notifications are queued with macOS (its limit is 64).
pub const QUEUED: usize = 60;

/// One alarm macOS holds: the reminder's id, its text and when.
pub type Queued = (String, String, u64);

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
    /// A repeating reminder: a series (series.rs).
    pub repeat: Option<Repeat>,
    /// The series' first occurrence: its wall-clock time and weekday or day of month. Moves
    /// only when the series itself is edited, never with a snooze.
    pub anchor: u64,
    /// When the current occurrence was due before any snooze. `due` is when it fires next.
    pub occurrence: u64,
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
            anchor: 0,
            occurrence: 0,
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
    notifications: Mutex<Option<std::sync::mpsc::Sender<Vec<Queued>>>>,
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
            // Files from before series: the current due time is the anchor.
            .map(|mut r: Reminder| {
                if r.occurrence == 0 {
                    r.occurrence = r.due;
                }
                if r.anchor == 0 {
                    r.anchor = r.occurrence;
                }
                r
            })
            .collect::<Vec<_>>()
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

    pub fn schedule_with(&self, sender: std::sync::mpsc::Sender<Vec<Queued>>) {
        let list = self.list.lock().unwrap();
        let _ = sender.send(queue(&list, now_ms(), &jiff::tz::TimeZone::system()));
        *self.notifications.lock().unwrap() = Some(sender);
    }

    pub fn reschedule(&self) {
        let list = self.list.lock().unwrap();
        self.schedule(&list);
    }

    fn schedule(&self, list: &[Reminder]) {
        if let Some(sender) = self.notifications.lock().unwrap().as_ref() {
            let _ = sender.send(queue(list, now_ms(), &jiff::tz::TimeZone::system()));
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
            anchor: due,
            occurrence: due,
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
        // A new time from the editor moves the whole series ("all future"), anchor included.
        if let Some(due) = change.due {
            r.due = due;
            r.occurrence = due;
            r.anchor = due;
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

    /// The user's answer to a reminder's card (docs/V1.md V1-R4, V1-R5).
    pub fn answer(&self, id: &str, answer: Answer, now: u64, tz: &jiff::tz::TimeZone) -> io::Result<bool> {
        let mut list = self.list.lock().unwrap();
        let mut next = list.clone();
        let Some(r) = next.iter_mut().find(|r| r.id == id && !r.done) else {
            return Ok(false);
        };
        let (action, due) = match (answer, &r.repeat) {
            (Answer::Snooze(until), _) => {
                r.due = until;
                r.fired = false;
                ("Snoozed", until)
            }
            (Answer::Done, None) | (Answer::Skip, None) => {
                r.done = true;
                (if answer == Answer::Done { "Completed" } else { "Skipped" }, r.occurrence)
            }
            (_, Some(repeat)) => {
                // From the occurrence, not from a snooze: Monday stays Monday.
                let handled = r.occurrence;
                r.occurrence = crate::series::next_after(r.anchor, repeat, handled.max(r.anchor), tz);
                // A long-missed series continues with its next occurrence from now.
                if r.occurrence <= now {
                    r.occurrence = crate::series::next_after(r.anchor, repeat, now, tz);
                }
                r.due = r.occurrence;
                r.fired = false;
                (if answer == Answer::Done { "Completed" } else { "Skipped" }, handled)
            }
        };
        push_history(r, action, due, now);
        self.write(&next)?;
        *list = next;
        Ok(true)
    }

    /// Moves series past occurrences that came and went (docs/V1.md V1-R6, V1-R8): an unanswered
    /// one is recorded as missed when the next one is due, and after a quit or sleep only the
    /// most recent missed occurrence shows. One-off reminders stay until answered. True when
    /// something changed.
    pub fn tick(&self, now: u64, tz: &jiff::tz::TimeZone) -> io::Result<bool> {
        let mut list = self.list.lock().unwrap();
        let mut next = list.clone();
        let mut changed = false;
        for r in next.iter_mut().filter(|r| !r.done && r.due <= now) {
            let Some(repeat) = r.repeat.clone() else { continue };
            let Some(latest) = crate::series::last_missed(r.anchor, &repeat, r.occurrence, now, tz) else { continue };
            push_history(r, "Missed", r.occurrence, now);
            r.occurrence = latest;
            r.due = latest;
            r.fired = false;
            changed = true;
        }
        if changed {
            self.write(&next)?;
            *list = next;
        }
        Ok(changed)
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

fn push_history(r: &mut Reminder, action: &str, due: u64, now: u64) {
    r.history.push(History { at: now, action: action.into(), due });
    if r.history.len() > 50 {
        r.history.drain(..r.history.len() - 50);
    }
}

/// What macOS should hold, soonest first (docs/V1.md V1-R7): every one-off still to come, then
/// each series' next occurrences in turn, at most `QUEUED`.
pub fn queue(list: &[Reminder], now: u64, tz: &jiff::tz::TimeZone) -> Vec<Queued> {
    let open: Vec<&Reminder> = list.iter().filter(|r| !r.done).collect();
    let mut out: Vec<Queued> = open
        .iter()
        .filter(|r| r.repeat.is_none() && !r.fired && r.due > now)
        .map(|r| (r.id.clone(), r.text.clone(), r.due))
        .collect();
    // Each series: its current occurrence (if still to come), then the ones after it.
    let mut cursors: Vec<(&Reminder, u64, bool)> = open.iter().filter(|r| r.repeat.is_some()).map(|r| (*r, r.occurrence.max(r.due), !r.fired && r.due > now)).collect();
    while out.len() < QUEUED && !cursors.is_empty() {
        for (r, at, first) in cursors.iter_mut() {
            if out.len() >= QUEUED {
                break;
            }
            if *first {
                *first = false;
                out.push((r.id.clone(), r.text.clone(), r.due));
                continue;
            }
            *at = crate::series::next_after(r.anchor, r.repeat.as_ref().unwrap(), (*at).max(now), tz);
            out.push((r.id.clone(), r.text.clone(), *at));
        }
    }
    out.sort_by_key(|(_, _, at)| *at);
    out.truncate(QUEUED);
    out
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
        assert_eq!(rx.recv().unwrap(), vec![(r.id.clone(), "alarm".to_string(), r.due)]);
        store.update(&r.id, &Change { due: Some(r.due + 60_000), ..Default::default() }).unwrap();
        assert_eq!(rx.recv().unwrap()[0].2, r.due + 60_000);
        let removed = store.remove(&r.id).unwrap().unwrap();
        assert!(rx.recv().unwrap().is_empty());
        store.restore(removed.clone()).unwrap();
        assert_eq!(rx.recv().unwrap().len(), 1);
        store.update(&r.id, &Change { done: Some(true), ..Default::default() }).unwrap();
        assert!(rx.recv().unwrap().is_empty(), "a finished reminder holds no alarm");
        let completed = store.list().remove(0);
        assert!(completed.done);
        assert_eq!(completed.history.last().unwrap().action, "Completed");
        assert_eq!(completed.history.last().unwrap().due, r.due + 60_000);
        assert!(store.add("", 0, "", "you", None).is_err());
        assert!(rx.try_recv().is_err());
        fs::remove_dir_all(dir).unwrap();
    }

    fn at(tz: &jiff::tz::TimeZone, d: i8, h: i8) -> u64 {
        crate::series::instant(jiff::civil::date(2026, 10, d).at(h, 0, 0, 0), tz)
    }

    #[test]
    fn a_snooze_never_moves_the_series_and_done_goes_to_the_next_occurrence() {
        let tz = jiff::tz::TimeZone::get("Asia/Tokyo").unwrap();
        let dir = std::env::temp_dir().join(format!("sidefolk-series-{}", std::process::id()));
        let store = Reminders::load(&dir, &Default::default());
        // Weekly on Monday 26 October at 09:00, snoozed to Tuesday, then done: next Monday.
        let r = store.add("plan the week", at(&tz, 26, 9), "", "you", Some(Repeat { every: "week".into(), n: 1 })).unwrap();
        store.answer(&r.id, Answer::Snooze(at(&tz, 27, 10)), at(&tz, 26, 9), &tz).unwrap();
        assert_eq!(store.list()[0].due, at(&tz, 27, 10));
        store.answer(&r.id, Answer::Done, at(&tz, 27, 10), &tz).unwrap();
        let next = store.list().remove(0);
        assert_eq!((next.due, next.occurrence, next.done), (crate::series::instant(jiff::civil::date(2026, 11, 2).at(9, 0, 0, 0), &tz), next.due, false));
        // Skip moves past one occurrence; a one-off is finished by Done.
        store.answer(&r.id, Answer::Skip, at(&tz, 27, 11), &tz).unwrap();
        assert_eq!(store.list()[0].due, crate::series::instant(jiff::civil::date(2026, 11, 9).at(9, 0, 0, 0), &tz));
        let once = store.add("call the bank", at(&tz, 27, 15), "", "you", None).unwrap();
        store.answer(&once.id, Answer::Done, at(&tz, 27, 15), &tz).unwrap();
        assert!(store.list().iter().find(|x| x.id == once.id).unwrap().done);
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn missed_occurrences_are_recorded_and_only_the_latest_shows() {
        let tz = jiff::tz::TimeZone::get("Asia/Tokyo").unwrap();
        let dir = std::env::temp_dir().join(format!("sidefolk-missed-{}", std::process::id()));
        let store = Reminders::load(&dir, &Default::default());
        let daily = store.add("drink water", at(&tz, 20, 9), "", "you", Some(Repeat { every: "day".into(), n: 1 })).unwrap();
        let once = store.add("send the invoice", at(&tz, 20, 15), "", "you", None).unwrap();
        // Shown on the 20th, never answered; the Mac slept until the 25th at 10:00.
        store.update(&daily.id, &Change { fired: Some(true), ..Default::default() }).unwrap();
        assert!(store.tick(at(&tz, 25, 10), &tz).unwrap());
        let list = store.list();
        let daily = list.iter().find(|x| x.id == daily.id).unwrap();
        assert_eq!((daily.due, daily.fired), (at(&tz, 25, 9), false));
        assert_eq!(daily.history.last().unwrap().action, "Missed");
        // The one-off stays where it was, overdue until answered.
        assert_eq!(list.iter().find(|x| x.id == once.id).unwrap().due, at(&tz, 20, 15));
        assert!(!store.tick(at(&tz, 25, 10), &tz).unwrap());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn macos_holds_one_offs_and_the_next_occurrences_of_each_series() {
        let tz = jiff::tz::TimeZone::get("Asia/Tokyo").unwrap();
        let now = at(&tz, 25, 10);
        let daily = Reminder { id: "d".into(), text: "water".into(), due: at(&tz, 25, 18), anchor: at(&tz, 20, 18), occurrence: at(&tz, 25, 18), repeat: Some(Repeat { every: "day".into(), n: 1 }), ..Default::default() };
        let once = Reminder { id: "o".into(), text: "bank".into(), due: at(&tz, 26, 9), occurrence: at(&tz, 26, 9), ..Default::default() };
        let done = Reminder { id: "x".into(), done: true, due: at(&tz, 26, 9), ..Default::default() };
        let q = queue(&[daily, once, done], now, &tz);
        assert_eq!(q.len(), QUEUED);
        assert_eq!(q[0], ("d".to_string(), "water".to_string(), at(&tz, 25, 18)));
        assert_eq!(q[1].0, "o");
        assert_eq!(q[2], ("d".to_string(), "water".to_string(), at(&tz, 26, 18)));
        assert!(q.iter().all(|(id, _, at)| id != "x" && *at > now));
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
