//! Shapes shared by every agent source, and the pending-permission registry.

use std::{
    collections::HashMap,
    sync::{
        Mutex,
        atomic::{AtomicU64, Ordering},
    },
};

use serde::Serialize;
use tauri::{AppHandle, Emitter};
use tokio::sync::oneshot;

/// One observable change in an agent session, already reduced to what the pet acts out.
#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct AgentEvent {
    pub source: &'static str,
    pub session: String,
    /// start | think | read | edit | run | tool | waiting | idle | message | done | failed | end
    pub kind: &'static str,
    pub detail: String,
    pub cwd: String,
}

pub fn emit(app: &AppHandle, event: AgentEvent) {
    let _ = app.emit("agent", event);
}

#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct PermissionAsk {
    pub id: String,
    pub source: &'static str,
    pub session: String,
    pub title: String,
    pub detail: String,
    pub cwd: String,
    /// Whether "answer in the terminal instead" is meaningful for this source.
    pub can_defer: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Decision {
    Allow,
    Deny,
    /// Leave the decision to the agent's own UI (the terminal prompt).
    Defer,
}

#[derive(Default)]
pub struct Permissions {
    next: AtomicU64,
    pending: Mutex<HashMap<String, oneshot::Sender<Decision>>>,
}

impl Permissions {
    pub fn open(&self, prefix: &str) -> (String, oneshot::Receiver<Decision>) {
        let id = format!("{prefix}-{}", self.next.fetch_add(1, Ordering::Relaxed));
        let (tx, rx) = oneshot::channel();
        self.pending.lock().unwrap().insert(id.clone(), tx);
        (id, rx)
    }

    pub fn resolve(&self, id: &str, decision: Decision) -> bool {
        match self.pending.lock().unwrap().remove(id) {
            Some(tx) => tx.send(decision).is_ok(),
            None => false,
        }
    }

    /// Drops a request that ended without an answer (timeout or the agent went away).
    pub fn close(&self, app: &AppHandle, id: &str) {
        self.pending.lock().unwrap().remove(id);
        let _ = app.emit("permission-closed", id);
    }
}

pub struct Shared {
    pub settings: Mutex<crate::settings::Store>,
    pub permissions: Permissions,
    pub codex: tokio::sync::Mutex<Option<std::sync::Arc<crate::codex::Codex>>>,
}

pub fn clip(text: &str, max: usize) -> String {
    let text = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if text.chars().count() <= max {
        return text;
    }
    let cut: String = text.chars().take(max.saturating_sub(1)).collect();
    format!("{}…", cut.trim_end())
}
