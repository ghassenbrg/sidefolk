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

/// Event conditions expire without becoming date reminders (V1-R13).
pub const EVENT_TTL_MS: u64 = 24 * 3_600_000;
const STORE_VERSION: u64 = 2;
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
    /// The series title while `text` is an override for the current occurrence.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub series_text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub event: Option<EventTrigger>,
}

/// Waiting conditions have no due time. Only a real, exact-project done event sets one.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct EventTrigger {
    pub expires: u64,
    #[serde(default)]
    pub triggered_at: Option<u64>,
    #[serde(default)]
    pub expired_at: Option<u64>,
}

impl Reminder {
    pub fn scheduled(&self) -> bool {
        !self.done && self.event.as_ref().is_none_or(|event| event.triggered_at.is_some() && event.expired_at.is_none())
    }
}

/// Normalize a resolved folder to the same real repository identity on both integration paths.
/// No command, model, fuzzy name or shell lookup runs here.
pub fn event_project(path: &str) -> io::Result<String> {
    if !std::path::Path::new(path).is_absolute() {
        return Err(io::Error::other("Choose a full project folder path."));
    }
    let path = std::fs::canonicalize(path)?;
    path.ancestors().find(|dir| dir.join(".git").exists())
        .map(|root| root.to_string_lossy().into_owned())
        .ok_or_else(|| io::Error::other("Choose a project folder containing a Git repository."))
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct History {
    pub at: u64,
    pub action: String,
    pub due: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Repeat {
    /// "day", "weekday", "week", "month" or "year". February 29 uses February 28
    /// in non-leap years, retaining February 29 as the yearly anchor.
    pub every: String,
    pub n: u32,
    /// Weekly on these days (0 Sunday … 6 Saturday), e.g. Monday and Thursday; empty means the
    /// anchor's weekday.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub days: Vec<u8>,
}

impl Repeat {
    pub fn valid(&self) -> bool {
        matches!(self.every.as_str(), "day" | "weekday" | "week" | "month" | "year")
            && (1..=52).contains(&self.n)
            && self.days.iter().all(|d| *d < 7)
            && (self.days.is_empty() || self.every == "week")
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
            series_text: None,
            event: None,
        }
    }
}

#[derive(Deserialize, Clone, Copy, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum EditScope { ThisOne, AllFuture }

#[derive(Deserialize, Default)]
pub struct Change {
    /// Absent retains the original update API. UI editors always name their scope and boundary.
    pub scope: Option<EditScope>,
    pub expected_occurrence: Option<u64>,
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
        let loaded = crate::store::load::<Vec<Reminder>>(&path, STORE_VERSION, serde_json::Value::is_array, |_, data| data);
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
        let text: String = text.split_whitespace().collect::<Vec<_>>().join(" ");
        if text.is_empty() {
            return Err(io::Error::other("A reminder needs some text"));
        }
        let mut list = self.list.lock().unwrap();
        if list.iter().filter(|r| !r.done && r.event.as_ref().is_none_or(|event| event.expired_at.is_none())).count() >= MAX_OPEN {
            return Err(io::Error::other("Too many open reminders"));
        }
        let now = now_ms();
        let repeat = repeat.filter(Repeat::valid);
        let first = repeat.as_ref().map(|rule| crate::series::next_after(due, rule, due.saturating_sub(1), &jiff::tz::TimeZone::system())).unwrap_or(due);
        let reminder = Reminder {
            id: next_id(now),
            text: text.chars().take(MAX_TEXT).collect(),
            due: first,
            project: project.to_string(),
            from: from.to_string(),
            created: now,
            anchor: due,
            occurrence: first,
            repeat,
            history: vec![History { at: now, action: "Created".into(), due, text: Some(text.chars().take(MAX_TEXT).collect()) }],
            ..Default::default()
        };
        let mut next = list.clone();
        next.push(reminder.clone());
        self.write(&next)?;
        *list = next;
        Ok(reminder)
    }

    /// The caller resolves and previews the exact repository before this durable write.
    pub fn add_event(&self, text: &str, project: &str, from: &str, now: u64) -> io::Result<Reminder> {
        let text = text.split_whitespace().collect::<Vec<_>>().join(" ");
        if text.is_empty() { return Err(io::Error::other("Enter what to remember.")); }
        let project = event_project(project)?;
        let expires = now.checked_add(EVENT_TTL_MS).ok_or_else(|| io::Error::other("Choose a valid reminder time."))?;
        let mut list = self.list.lock().unwrap();
        if list.iter().filter(|r| !r.done && r.event.as_ref().is_none_or(|event| event.expired_at.is_none())).count() >= MAX_OPEN {
            return Err(io::Error::other("Too many open reminders"));
        }
        let reminder = Reminder {
            id: next_id(now), text: text.chars().take(MAX_TEXT).collect(), project,
            from: from.into(), created: now,
            event: Some(EventTrigger { expires, triggered_at: None, expired_at: None }),
            history: vec![History { at: now, action: "Waiting for project completion".into(), due: 0, text: Some(text) }],
            ..Default::default()
        };
        let mut next = list.clone(); next.push(reminder.clone());
        self.write(&next)?; *list = next;
        Ok(reminder)
    }

    /// Called only for an observed done event, never idle/end/failed or a journal replay.
    /// The canonical project must match exactly. An event at the expiry boundary is too late.
    pub fn project_done(&self, project: &str, now: u64) -> io::Result<bool> {
        let mut list = self.list.lock().unwrap();
        let mut next = list.clone();
        let mut changed = false;
        for r in next.iter_mut().filter(|r| !r.done && r.project == project) {
            let Some(event) = r.event.as_mut() else { continue };
            if event.triggered_at.is_some() || event.expired_at.is_some() || now < r.created { continue; }
            if now >= event.expires {
                event.expired_at = Some(now);
                push_history(r, "Expired: no project completion within 24 hours", 0, now);
            } else {
                event.triggered_at = Some(now);
                r.due = now; r.occurrence = now; r.anchor = now; r.fired = false;
                push_history(r, "Project completed", now, now);
            }
            changed = true;
        }
        if changed { self.write(&next)?; *list = next; }
        Ok(changed)
    }

    pub fn update(&self, id: &str, change: &Change) -> io::Result<bool> {
        self.update_at(id, change, now_ms(), &jiff::tz::TimeZone::system())
    }

    /// Fixed clock entry point; explicit scopes are validated before any mutation is saved.
    pub fn update_at(&self, id: &str, change: &Change, now: u64, tz: &jiff::tz::TimeZone) -> io::Result<bool> {
        let mut list = self.list.lock().unwrap();
        let mut next = list.clone();
        let Some(r) = next.iter_mut().find(|r| r.id == id) else {
            return Ok(false);
        };
        if r.event.is_some() && (change.repeat.is_some() || change.clear_repeat
            || !r.scheduled() && (change.due.is_some() || change.done.is_some() || change.fired.is_some() || change.completed)) {
            return Err(io::Error::other("Please delete this event condition instead of rescheduling it."));
        }
        if change.scope.is_some() && change.expected_occurrence.is_none() {
            return Err(io::Error::other("Please reopen this reminder before choosing an edit scope."));
        }
        if change.expected_occurrence.is_some_and(|at| at != r.occurrence) {
            return Err(io::Error::other("Please reopen this reminder; its occurrence changed."));
        }
        if change.scope.is_some() && (r.done || change.done.is_some() || change.completed || change.fired.is_some()) {
            return Err(io::Error::other("Choose Done separately from editing a reminder."));
        }
        if change.repeat.as_ref().is_some_and(|repeat| !repeat.valid()) {
            return Err(io::Error::other("Choose a valid repeat interval (1–52)"));
        }
        let one = change.scope == Some(EditScope::ThisOne);
        if one && (r.repeat.is_none() || change.repeat.is_some() || change.clear_repeat) {
            return Err(io::Error::other("Choose All future to change a repeat rule."));
        }
        let moving = change.due.is_some_and(|due| due != r.due);
        if change.scope.is_some() && moving && change.due.is_some_and(|due| due <= now) {
            return Err(io::Error::other("That time has passed. Choose a later one."));
        }
        let old_due = if change.scope.is_some() { r.occurrence } else { r.due };
        let old_text = r.text.clone();
        // Ending an override restores the series title before applying a series edit.
        if !one && (change.text.is_some() || change.repeat.is_some() || change.clear_repeat || moving) {
            reset_title(r);
        }
        if let Some(text) = &change.text {
            let text: String = text.split_whitespace().collect::<Vec<_>>().join(" ");
            if text.is_empty() { return Err(io::Error::other("Enter what to remember.")); }
            if one && r.series_text.is_none() { r.series_text = Some(r.text.clone()); }
            r.text = text.chars().take(MAX_TEXT).collect();
        }
        let rule_changed = change.clear_repeat && r.repeat.is_some()
            || change.repeat.as_ref().is_some_and(|repeat| Some(repeat) != r.repeat.as_ref());
        if change.clear_repeat { r.repeat = None; }
        else if let Some(repeat) = &change.repeat { r.repeat = Some(repeat.clone()); }
        if let Some(done) = change.done { r.done = done; }
        if let Some(due) = change.due && (moving || change.scope.is_none()) {
            r.due = due;
            if !one {
                let wall = crate::series::wall(due, tz);
                // A clock-only edit in February must retain a 31st/February 29 rule.
                // Changing the calendar date explicitly still chooses a new anchor.
                let keep_date = change.scope.is_some() && !rule_changed && r.repeat.is_some()
                    && wall.date() == crate::series::wall(r.occurrence, tz).date();
                r.anchor = if keep_date {
                    crate::series::instant(crate::series::wall(r.anchor, tz).date().to_datetime(wall.time()), tz)
                } else { due };
                r.occurrence = due;
            }
            r.fired = false;
        }
        if !one && rule_changed && !moving && change.scope.is_some() {
            r.anchor = r.occurrence;
        }
        if !one && (rule_changed || moving) && change.scope.is_some() && let Some(repeat) = &r.repeat {
            r.occurrence = crate::series::next_after(r.anchor, repeat, r.occurrence.saturating_sub(1), tz);
            r.due = r.occurrence;
            r.fired = false;
        }
        if let Some(fired) = change.fired { r.fired = fired; }
        let action = if change.completed || change.done == Some(true) { Some("Completed") }
            else if change.text.is_some() || change.repeat.is_some() || change.clear_repeat { Some("Edited") }
            else if change.due.is_some() { Some("Rescheduled") } else { None };
        if let Some(action) = action {
            r.history.push(History { at: now, action: action.into(), due: old_due, text: Some(old_text) });
        }
        self.write(&next)?;
        *list = next;
        Ok(true)
    }

    /// The user's answer to a reminder's card (docs/V1.md V1-R4, V1-R5).
    pub fn answer(&self, id: &str, answer: Answer, now: u64, tz: &jiff::tz::TimeZone) -> io::Result<bool> {
        let mut list = self.list.lock().unwrap();
        let mut next = list.clone();
        let Some(r) = next.iter_mut().find(|r| r.id == id && r.scheduled()) else {
            return Ok(false);
        };
        if matches!(answer, Answer::Snooze(until) if until <= now) {
            return Err(io::Error::other("That time has passed. Choose a later one."));
        }
        if answer == Answer::Skip && r.repeat.is_none() {
            return Err(io::Error::other("Choose Done for a reminder that does not repeat."));
        }
        let handled_text = r.text.clone();
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
                reset_title(r);
                (if answer == Answer::Done { "Completed" } else { "Skipped" }, handled)
            }
        };
        r.history.push(History { at: now, action: action.into(), due, text: Some(handled_text) });
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
        for r in next.iter_mut().filter(|r| !r.done) {
            if let Some(event) = r.event.as_mut() {
                if event.triggered_at.is_none() && event.expired_at.is_none() && now >= event.expires {
                    event.expired_at = Some(now);
                    push_history(r, "Expired: no project completion within 24 hours", 0, now);
                    changed = true;
                }
                continue;
            }
            let Some(repeat) = r.repeat.clone() else { continue };
            let Some(latest) = crate::series::last_missed(r.anchor, &repeat, r.occurrence, now, tz) else { continue };
            push_history(r, "Missed", r.occurrence, now);
            reset_title(r);
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
        crate::store::save(&self.path, STORE_VERSION, &list)?;
        self.schedule(list);
        Ok(())
    }
}

fn next_id(now: u64) -> String {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    format!("r{now}-{}", NEXT.fetch_add(1, Ordering::Relaxed))
}

fn reset_title(r: &mut Reminder) {
    if let Some(text) = r.series_text.take() { r.text = text; }
}

fn push_history(r: &mut Reminder, action: &str, due: u64, now: u64) {
    r.history.push(History { at: now, action: action.into(), due, text: Some(r.text.clone()) });
}

/// What macOS should hold, soonest first (docs/V1.md V1-R7): every one-off still to come, then
/// each series' next occurrences in turn, at most `QUEUED`.
pub fn queue(list: &[Reminder], now: u64, tz: &jiff::tz::TimeZone) -> Vec<Queued> {
    let open: Vec<&Reminder> = list.iter().filter(|r| r.scheduled()).collect();
    let mut out: Vec<Queued> = open
        .iter()
        .filter(|r| r.repeat.is_none() && !r.fired && r.due > now)
        .map(|r| (r.id.clone(), r.text.clone(), r.due))
        .collect();
    // Each series: its current occurrence (if still to come), then the ones after it.
    let mut cursors: Vec<(&Reminder, u64, bool)> = open.iter().filter(|r| r.repeat.is_some()).map(|r| (*r, r.occurrence, !r.fired && r.due > now && r.due < crate::series::next_after(r.anchor, r.repeat.as_ref().unwrap(), r.occurrence, tz))).collect();
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
            out.push((r.id.clone(), r.series_text.as_ref().unwrap_or(&r.text).clone(), *at));
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
        let r = store.add("plan the week", at(&tz, 26, 9), "", "you", Some(Repeat { every: "week".into(), n: 1, days: vec![] })).unwrap();
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
        let daily = store.add("drink water", at(&tz, 20, 9), "", "you", Some(Repeat { every: "day".into(), n: 1, days: vec![] })).unwrap();
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
        let daily = Reminder { id: "d".into(), text: "water".into(), due: at(&tz, 25, 18), anchor: at(&tz, 20, 18), occurrence: at(&tz, 25, 18), repeat: Some(Repeat { every: "day".into(), n: 1, days: vec![] }), ..Default::default() };
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
        // Completion history persists until the user explicitly deletes it.
        store.update(&r.id, &Change { done: Some(true), ..Default::default() }).unwrap();
        assert!(Reminders::load(&dir, &Default::default()).list()[0].done);
        assert!(!store.update("missing", &Change::default()).unwrap());
        let weekly = Repeat { every: "week".into(), n: 2, days: vec![] };
        let r = store.add("send the report", now_ms() + 60_000, "", "you", Some(weekly.clone())).unwrap();
        assert_eq!(r.repeat, Some(weekly.clone()));
        store.update(&r.id, &serde_json::from_str::<Change>(r#"{"text":"new title"}"#).unwrap()).unwrap();
        assert_eq!(store.list().iter().find(|x| x.id == r.id).unwrap().repeat, Some(weekly));
        store.update(&r.id, &serde_json::from_str::<Change>(r#"{"repeat":{"every":"day","n":3}}"#).unwrap()).unwrap();
        assert_eq!(store.list().iter().find(|x| x.id == r.id).unwrap().repeat.as_ref().unwrap().n, 3);
        assert!(store.update(&r.id, &serde_json::from_str::<Change>(r#"{"repeat":{"every":"day","n":0}}"#).unwrap()).is_err());
        store.update(&r.id, &serde_json::from_str::<Change>(r#"{"clear_repeat":true}"#).unwrap()).unwrap();
        assert_eq!(Reminders::load(&dir, &Default::default()).list().iter().find(|x| x.id == r.id).unwrap().repeat, None);
        let odd = store.add("odd", now_ms() + 60_000, "", "you", Some(Repeat { every: "hour".into(), n: 1, days: vec![] })).unwrap();
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
    fn scoped_fixture(name: &str) -> (PathBuf, Reminders, jiff::tz::TimeZone, Reminder) {
        let dir = std::env::temp_dir().join(format!("sidefolk-scoped-{name}-{}", std::process::id()));
        let store = Reminders::load(&dir, &Default::default());
        let tz = jiff::tz::TimeZone::get("Asia/Tokyo").unwrap();
        let r = store.add("Weekly plan", at(&tz, 26, 9), "", "you", Some(Repeat { every: "week".into(), n: 1, days: vec![] })).unwrap();
        (dir, store, tz, r)
    }

    #[test]
    fn occurrence_title_and_time_override_survives_reload_then_restores_the_series() {
        let (dir, store, tz, r) = scoped_fixture("override");
        let history = r.history.clone();
        store.update_at(&r.id, &Change {
            scope: Some(EditScope::ThisOne), expected_occurrence: Some(r.occurrence),
            text: Some("Plan with guest".into()), due: Some(at(&tz, 27, 10)), ..Default::default()
        }, at(&tz, 25, 12), &tz).unwrap();
        let overridden = Reminders::load(&dir, &Default::default()).list().remove(0);
        assert_eq!((overridden.anchor, overridden.occurrence, overridden.due), (r.anchor, r.occurrence, at(&tz, 27, 10)));
        assert_eq!(overridden.text, "Plan with guest");
        assert_eq!(overridden.series_text.as_deref(), Some("Weekly plan"));
        assert_eq!(&overridden.history[..history.len()], &history);
        let q = queue(&[overridden], at(&tz, 25, 12), &tz);
        assert_eq!(q[0].1, "Plan with guest");
        assert_eq!(q[1].1, "Weekly plan");
        store.answer(&r.id, Answer::Done, at(&tz, 27, 11), &tz).unwrap();
        let next = store.list().remove(0);
        assert_eq!(next.text, "Weekly plan");
        assert_eq!(next.anchor, r.anchor);
        assert_eq!(crate::series::wall(next.due, &tz).date(), jiff::civil::date(2026, 11, 2));
        assert_eq!(next.history.last().unwrap().text.as_deref(), Some("Plan with guest"));
        assert_eq!(next.history.last().unwrap().due, r.occurrence);
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn next_regular_firing_rolls_over_a_far_future_override_without_moving_anchor() {
        let (dir, store, tz, r) = scoped_fixture("rollover");
        store.update_at(&r.id, &Change {
            scope: Some(EditScope::ThisOne), expected_occurrence: Some(r.occurrence),
            text: Some("Only this week".into()), due: Some(at(&tz, 30, 10) + 7 * 86_400_000), ..Default::default()
        }, at(&tz, 25, 12), &tz).unwrap();
        let next_monday = crate::series::instant(jiff::civil::date(2026, 11, 2).at(9, 0, 0, 0), &tz);
        let q = queue(&store.list(), at(&tz, 25, 12), &tz);
        assert_eq!(q[0], (r.id.clone(), "Weekly plan".into(), next_monday));
        assert!(store.tick(next_monday, &tz).unwrap());
        let next = store.list().remove(0);
        assert_eq!((next.anchor, next.occurrence, next.due), (r.anchor, next_monday, next_monday));
        assert_eq!(next.text, "Weekly plan");
        assert_eq!(next.history.last().unwrap().text.as_deref(), Some("Only this week"));
        assert!(!store.tick(next_monday, &tz).unwrap());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn all_future_changes_from_current_boundary_and_preserves_completed_history() {
        let (dir, store, tz, r) = scoped_fixture("future");
        store.answer(&r.id, Answer::Done, at(&tz, 26, 10), &tz).unwrap();
        let before = store.list().remove(0);
        let boundary = before.occurrence;
        // A title-only edit never reanchors the series, including a retained snooze.
        store.answer(&r.id, Answer::Snooze(boundary + 3_600_000), at(&tz, 27, 9), &tz).unwrap();
        store.update_at(&r.id, &Change { scope: Some(EditScope::AllFuture), expected_occurrence: Some(boundary), text: Some("New plan".into()), ..Default::default() }, at(&tz, 27, 10), &tz).unwrap();
        let renamed = store.list().remove(0);
        assert_eq!((renamed.anchor, renamed.occurrence, renamed.due), (r.anchor, boundary, boundary + 3_600_000));
        // A rule/time edit starts at this boundary; completed entries stay byte-for-byte.
        store.update_at(&r.id, &Change {
            scope: Some(EditScope::AllFuture), expected_occurrence: Some(boundary),
            due: Some(boundary + 2 * 3_600_000), repeat: Some(Repeat { every: "day".into(), n: 2, days: vec![] }), ..Default::default()
        }, at(&tz, 27, 10), &tz).unwrap();
        let edited = store.list().remove(0);
        assert_eq!(&edited.history[..before.history.len()], &before.history);
        assert_eq!(edited.anchor, boundary + 2 * 3_600_000);
        store.answer(&r.id, Answer::Done, edited.due, &tz).unwrap();
        assert_eq!(store.list()[0].due, edited.anchor + 2 * 86_400_000);
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn unsafe_scopes_and_past_snoozes_fail_without_mutation() {
        let (dir, store, tz, r) = scoped_fixture("safety");
        let now = at(&tz, 25, 12);
        for change in [
            Change { scope: Some(EditScope::ThisOne), expected_occurrence: Some(r.occurrence), repeat: Some(Repeat { every: "day".into(), n: 1, days: vec![] }), ..Default::default() },
            Change { scope: Some(EditScope::ThisOne), expected_occurrence: Some(r.occurrence), clear_repeat: true, ..Default::default() },
            Change { scope: Some(EditScope::AllFuture), expected_occurrence: Some(r.occurrence - 1), text: Some("Stale".into()), ..Default::default() },
            Change { scope: Some(EditScope::AllFuture), ..Default::default() },
            Change { scope: Some(EditScope::ThisOne), expected_occurrence: Some(r.occurrence), due: Some(now), ..Default::default() },
            Change { scope: Some(EditScope::AllFuture), expected_occurrence: Some(r.occurrence), done: Some(true), ..Default::default() },
        ] {
            assert!(store.update_at(&r.id, &change, now, &tz).is_err());
            assert_eq!(store.list(), vec![r.clone()]);
        }
        assert!(store.answer(&r.id, Answer::Snooze(now), now, &tz).is_err());
        let once = store.add("One off", r.due, "", "you", None).unwrap();
        assert!(store.update_at(&once.id, &Change { scope: Some(EditScope::ThisOne), expected_occurrence: Some(once.occurrence), text: Some("Wrong scope".into()), ..Default::default() }, now, &tz).is_err());
        assert!(store.answer(&once.id, Answer::Skip, now, &tz).is_err());
        assert!(!store.list().iter().find(|x| x.id == once.id).unwrap().done);
        // Skip keeps the series. Whole-series delete and Undo retain all metadata.
        store.answer(&r.id, Answer::Skip, now, &tz).unwrap();
        let skipped = store.list().iter().find(|x| x.id == r.id).unwrap().clone();
        assert_eq!(skipped.anchor, r.anchor);
        assert_eq!(skipped.history.last().unwrap().action, "Skipped");
        let removed = store.remove(&r.id).unwrap().unwrap();
        store.restore(removed.clone()).unwrap();
        assert_eq!(store.list().iter().find(|x| x.id == r.id), Some(&removed));
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn legacy_updates_keep_their_scope_defaults_and_completed_history_has_no_item_cap() {
        let (dir, store, tz, r) = scoped_fixture("legacy");
        store.answer(&r.id, Answer::Skip, at(&tz, 25, 12), &tz).unwrap();
        let current = store.list().remove(0);
        let daily = Repeat { every: "day".into(), n: 1, days: vec![] };
        // Legacy MCP repeat-only updates retain their original anchor semantics.
        store.update_at(&r.id, &Change { repeat: Some(daily), ..Default::default() }, at(&tz, 25, 12), &tz).unwrap();
        assert_eq!(store.list()[0].anchor, r.anchor);
        // A legacy explicit due remains a series reschedule, even if unchanged.
        store.update_at(&r.id, &Change { due: Some(current.due), ..Default::default() }, at(&tz, 25, 12), &tz).unwrap();
        assert_eq!(store.list()[0].anchor, current.due);
        for _ in 0..55 { store.answer(&r.id, Answer::Done, at(&tz, 25, 12), &tz).unwrap(); }
        let reloaded = Reminders::load(&dir, &Default::default()).list().remove(0);
        assert_eq!(reloaded.history.iter().filter(|entry| entry.action == "Completed").count(), 55);
        assert_eq!(reloaded.history.first().unwrap().action, "Created");
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn all_future_clock_edits_keep_clamped_monthly_and_yearly_calendar_dates() {
        for (name, every, anchor_date, next_date) in [
            ("month-clock", "month", jiff::civil::date(2027, 1, 31), jiff::civil::date(2027, 3, 31)),
            ("year-clock", "year", jiff::civil::date(2024, 2, 29), jiff::civil::date(2026, 2, 28)),
        ] {
            let (dir, store, tz, original) = scoped_fixture(name);
            store.remove(&original.id).unwrap();
            let anchor = crate::series::instant(anchor_date.at(9, 0, 0, 0), &tz);
            let r = store.add("Calendar", anchor, "", "you", Some(Repeat { every: every.into(), n: 1, days: vec![] })).unwrap();
            store.answer(&r.id, Answer::Done, anchor, &tz).unwrap();
            let clamped = store.list().remove(0);
            assert_eq!(crate::series::wall(clamped.due, &tz).day(), 28);
            store.update_at(&r.id, &Change {
                scope: Some(EditScope::AllFuture), expected_occurrence: Some(clamped.occurrence),
                due: Some(clamped.due + 3_600_000), ..Default::default()
            }, clamped.due - 3_600_000, &tz).unwrap();
            let edited = store.list().remove(0);
            assert_eq!(crate::series::wall(edited.anchor, &tz).date(), anchor_date);
            assert_eq!(crate::series::wall(edited.anchor, &tz).hour(), 10);
            assert_eq!(edited.history[..clamped.history.len()], clamped.history);
            store.answer(&r.id, Answer::Done, edited.due, &tz).unwrap();
            assert_eq!(store.list()[0].due, crate::series::instant(next_date.at(10, 0, 0, 0), &tz));
            fs::remove_dir_all(dir).unwrap();
        }
    }

    fn event_fixture(name: &str) -> (PathBuf, Reminders, String, u64) {
        let dir = std::env::temp_dir().join(format!("sidefolk-event-{name}-{}", std::process::id()));
        fs::create_dir_all(dir.join(".git")).unwrap();
        let project = fs::canonicalize(&dir).unwrap().to_string_lossy().into_owned();
        let store = Reminders::load(&dir, &Default::default());
        (dir, store, project, 1_000_000_000)
    }

    #[test]
    fn event_condition_persists_without_alarm_and_only_exact_next_done_triggers_once() {
        let (dir, store, project, now) = event_fixture("done");
        let r = store.add_event("Review results", &project, "you", now).unwrap();
        let tz = jiff::tz::TimeZone::get("Asia/Tokyo").unwrap();
        assert!(!r.scheduled());
        assert_eq!(r.due, 0);
        assert!(queue(&store.list(), now, &tz).is_empty());
        let reloaded = Reminders::load(&dir, &Default::default());
        assert_eq!(reloaded.list(), vec![r.clone()]);
        assert!(!reloaded.project_done(&format!("{project}-other"), now + 1).unwrap());
        assert!(!reloaded.project_done(&project, now - 1).unwrap(), "old events cannot satisfy a newly saved condition");
        assert!(reloaded.project_done(&project, now + 1000).unwrap());
        let triggered = reloaded.list().remove(0);
        assert_eq!(triggered.event.as_ref().unwrap().triggered_at, Some(now + 1000));
        assert_eq!((triggered.due, triggered.occurrence), (now + 1000, now + 1000));
        assert!(triggered.scheduled());
        assert!(!reloaded.project_done(&project, now + 2000).unwrap());
        assert!(!reloaded.tick(now + EVENT_TTL_MS * 2, &tz).unwrap(), "triggered conditions become ordinary one-offs");
        reloaded.answer(&r.id, Answer::Done, now + 2000, &tz).unwrap();
        assert!(Reminders::load(&dir, &Default::default()).list()[0].done);
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn event_expiry_is_a_visible_persisted_note_and_never_a_due_reminder() {
        for via_done in [false, true] {
            let (dir, store, project, now) = event_fixture(if via_done { "expire-done" } else { "expire-tick" });
            let r = store.add_event("api finishes", &project, "you", now).unwrap();
            let tz = jiff::tz::TimeZone::get("Asia/Tokyo").unwrap();
            assert!(!store.tick(now + EVENT_TTL_MS - 1, &tz).unwrap());
            assert!(!store.answer(&r.id, Answer::Snooze(now + 1000), now, &tz).unwrap());
            assert!(store.update_at(&r.id, &Change { due: Some(now + 1000), ..Default::default() }, now, &tz).is_err());
            if via_done { assert!(store.project_done(&project, now + EVENT_TTL_MS).unwrap()); }
            else { assert!(store.tick(now + EVENT_TTL_MS, &tz).unwrap()); }
            let expired = Reminders::load(&dir, &Default::default()).list().remove(0);
            assert_eq!(expired.event.as_ref().unwrap().expired_at, Some(now + EVENT_TTL_MS));
            assert_eq!(expired.event.as_ref().unwrap().triggered_at, None);
            assert_eq!(expired.due, 0);
            assert!(!expired.done, "expiry remains visible, never reported as completion");
            assert!(expired.history.last().unwrap().action.contains("Expired: no project completion"));
            assert!(queue(std::slice::from_ref(&expired), now, &tz).is_empty());
            assert!(!store.project_done(&project, now + EVENT_TTL_MS + 1).unwrap());
            assert!(!store.tick(now + EVENT_TTL_MS + 1, &tz).unwrap());
            assert!(!store.answer(&r.id, Answer::Done, now + EVENT_TTL_MS + 1, &tz).unwrap());
            assert_eq!(store.list(), vec![expired]);
            fs::remove_dir_all(dir).unwrap();
        }
    }

    #[test]
    fn event_saves_and_transitions_are_atomic_when_persistence_fails() {
        let (dir, store, project, now) = event_fixture("failure");
        let r = store.add_event("api finishes", &project, "you", now).unwrap();
        fs::remove_file(dir.join("reminders.json")).unwrap();
        fs::create_dir(dir.join("reminders.json")).unwrap();
        assert!(store.add_event("Another", &project, "you", now + 1).is_err());
        assert_eq!(store.list(), vec![r.clone()]);
        assert!(store.project_done(&project, now + 2).is_err());
        assert_eq!(store.list(), vec![r.clone()]);
        assert!(store.tick(now + EVENT_TTL_MS, &jiff::tz::TimeZone::system()).is_err());
        assert_eq!(store.list(), vec![r]);
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn version_one_migrates_by_defaults_and_old_completions_are_retained_in_version_two() {
        let (dir, _, _, _) = event_fixture("migration");
        let path = dir.join("reminders.json");
        let old = serde_json::json!({ "version": 1, "data": [{
            "id": "old", "text": "Finished years ago", "due": 1, "created": 1, "done": true,
            "history": [{ "at": 2, "action": "Completed", "due": 1 }]
        }] });
        fs::write(&path, serde_json::to_vec(&old).unwrap()).unwrap();
        let store = Reminders::load(&dir, &Default::default());
        let r = store.list().remove(0);
        assert!(r.done);
        assert_eq!(r.anchor, 1);
        assert!(r.event.is_none() && r.series_text.is_none());
        assert_eq!(r.history.len(), 1);
        assert!(r.history[0].text.is_none());
        store.update(&r.id, &Change { text: Some("Still retained".into()), ..Default::default() }).unwrap();
        let saved: serde_json::Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
        assert_eq!(saved["version"], 2);
        let reloaded = Reminders::load(&dir, &Default::default()).list().remove(0);
        assert!(reloaded.done);
        assert_eq!(reloaded.history[0], r.history[0]);
        fs::remove_dir_all(dir).unwrap();
    }

}
