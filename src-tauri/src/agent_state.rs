//! Bounded native session state survives webview reloads. No transcript or disk history.
use crate::bus::AgentEvent;
use serde::Serialize;
use std::{collections::HashMap, sync::Mutex};

const CAP: usize = 128;
const STALE_MS: u64 = 10 * 60_000;
#[derive(Clone, Serialize)]
pub struct Recorded { pub at: u64, #[serde(flatten)] pub event: AgentEvent }
#[derive(Clone)]
struct Session { prompt: Option<Recorded>, latest: Recorded }
#[derive(Default)]
struct State { sessions: HashMap<String, Session>, outcomes: HashMap<String, Session> }
#[derive(Default)]
pub struct Ledger(Mutex<State>);

impl Ledger {
    pub fn record(&self, event: &AgentEvent, at: u64) {
        if event.session.is_empty() { return; }
        let mut state = self.0.lock().unwrap();
        let key = format!("{}:{}", event.source, event.session);
        if matches!(event.kind, "idle" | "end") { state.sessions.remove(&key); return; }
        if event.kind == "message" { return; }
        let mut entry = state.sessions.remove(&key).unwrap_or_else(|| Session { prompt: None, latest: Recorded { at, event: event.clone() } });
        let mut event = event.clone();
        event.detail = if event.kind == "prompt" { event.detail.lines().next().unwrap_or_default().chars().take(500).collect() } else { event.detail.chars().take(500).collect() };
        entry.latest = Recorded { at, event };
        if entry.latest.event.kind == "prompt" && entry.prompt.is_none() { entry.prompt = Some(entry.latest.clone()); }
        if matches!(entry.latest.event.kind, "done" | "failed") {
            state.outcomes.insert(format!("{}:{}", entry.latest.event.source, entry.latest.event.project), entry);
        } else { state.sessions.insert(key, entry); }
        trim(&mut state.sessions); trim(&mut state.outcomes);
    }

    pub fn snapshot(&self, now: u64) -> Vec<Recorded> {
        let state = self.0.lock().unwrap();
        let mut events = Vec::new();
        for entry in state.sessions.values().filter(|s| now.saturating_sub(s.latest.at) < STALE_MS).chain(state.outcomes.values()) {
            if let Some(prompt) = &entry.prompt { events.push(prompt.clone()); }
            events.push(entry.latest.clone());
        }
        events.sort_by_key(|e| e.at);
        events
    }
}
fn trim(entries: &mut HashMap<String, Session>) {
    if entries.len() > CAP && let Some(key) = entries.iter().min_by_key(|(_, s)| s.latest.at).map(|(k, _)| k.clone()) { entries.remove(&key); }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn event(session: &str, kind: &'static str, detail: &str) -> AgentEvent { AgentEvent::new("claude", session, kind, detail.into(), "") }
    #[test]
    fn reload_keeps_first_prompt_latest_state_and_completion_after_end() {
        let ledger = Ledger::default();
        ledger.record(&event("s", "prompt", "First request\nprivate second line"), 1);
        ledger.record(&event("s", "prompt", "Second request"), 2);
        ledger.record(&event("s", "edit", "main.rs"), 3);
        let snapshot = ledger.snapshot(4);
        assert_eq!(snapshot.len(), 2);
        assert_eq!(snapshot[0].event.detail, "First request");
        assert_eq!((snapshot[1].event.kind, snapshot[1].at), ("edit", 3));
        ledger.record(&event("s", "done", ""), 5);
        ledger.record(&event("s", "end", ""), 6);
        let snapshot = ledger.snapshot(7);
        assert_eq!(snapshot[0].event.detail, "First request");
        assert_eq!(snapshot[1].event.kind, "done");
    }
    #[test]
    fn snapshots_drop_stale_sessions_and_bound_retained_state() {
        let ledger = Ledger::default();
        for i in 0..200 { ledger.record(&event(&i.to_string(), "think", ""), i); }
        assert_eq!(ledger.snapshot(200).len(), CAP);
        assert!(ledger.snapshot(STALE_MS + 200).is_empty());
    }
}
