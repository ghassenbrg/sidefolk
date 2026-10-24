//! Shapes shared by every agent source, and the pending-permission registry.

use std::{
    collections::HashMap,
    path::Path,
    sync::{
        LazyLock, Mutex,
        atomic::{AtomicU64, Ordering},
    },
};

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};
use tokio::sync::oneshot;

/// One observable change in an agent session, already reduced to what the pet acts out.
#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct AgentEvent {
    pub source: &'static str,
    pub session: String,
    /// start | prompt | think | read | edit | run | tool | waiting | idle | message | done | failed | end
    pub kind: &'static str,
    pub detail: String,
    pub cwd: String,
    /// Git root of `cwd`; empty outside a repository. Pets are bound to projects by this.
    pub project: String,
}

impl AgentEvent {
    pub fn new(source: &'static str, session: &str, kind: &'static str, detail: String, cwd: &str) -> Self {
        Self {
            source,
            session: session.to_string(),
            kind,
            detail,
            cwd: cwd.to_string(),
            project: project_root(cwd),
        }
    }
}

/// Shows the event on the pets, and keeps the ones worth a briefing in the journal.
pub fn emit(app: &AppHandle, event: AgentEvent) {
    if matches!(event.kind, "start" | "prompt" | "waiting" | "done" | "failed" | "end") {
        note(app, event.source, &event.session, &event.project, event.kind, &event.detail);
    }
    let _ = app.emit("agent", event);
}

/// Adds a journal entry. A full disk must not stop the pet, so failures are only logged.
pub fn note(app: &AppHandle, source: &str, session: &str, project: &str, kind: &str, detail: &str) {
    let Some(shared) = app.try_state::<std::sync::Arc<Shared>>() else { return };
    let entry = crate::journal::Entry {
        at: crate::journal::now_ms(),
        source: source.into(),
        session: session.into(),
        project: project.into(),
        kind: kind.into(),
        detail: detail.into(),
    };
    if let Err(error) = shared.journal.record(&entry) {
        eprintln!("sidefolk: journal: {error}");
    }
}

/// The nearest folder at or above `cwd` that contains `.git` (a directory, or a file in
/// worktrees and submodules). Hooks fire on every tool call, so answers are cached.
pub fn project_root(cwd: &str) -> String {
    static CACHE: LazyLock<Mutex<HashMap<String, String>>> = LazyLock::new(Default::default);
    if cwd.is_empty() {
        return String::new();
    }
    if let Some(root) = CACHE.lock().unwrap().get(cwd) {
        return root.clone();
    }
    let root = Path::new(cwd)
        .ancestors()
        .find(|dir| dir.join(".git").exists())
        .map(|dir| dir.display().to_string())
        .unwrap_or_default();
    CACHE.lock().unwrap().insert(cwd.to_string(), root.clone());
    root
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
    pub project: String,
    /// Whether "answer in the terminal instead" is meaningful for this source.
    pub can_defer: bool,
    /// command | file | web | tool: lets the card say what is being asked in plain words.
    pub kind: &'static str,
    /// Unix ms when the agent stops waiting (the card then says it expired).
    pub expires: u64,
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

/// Tool calls from agents (MCP) waiting for the page to answer.
#[derive(Default)]
pub struct Replies {
    next: AtomicU64,
    pending: Mutex<HashMap<String, oneshot::Sender<serde_json::Value>>>,
}

impl Replies {
    pub fn open(&self) -> (String, oneshot::Receiver<serde_json::Value>) {
        let id = format!("mcp-{}", self.next.fetch_add(1, Ordering::Relaxed));
        let (tx, rx) = oneshot::channel();
        self.pending.lock().unwrap().insert(id.clone(), tx);
        (id, rx)
    }

    pub fn resolve(&self, id: &str, value: serde_json::Value) -> bool {
        match self.pending.lock().unwrap().remove(id) {
            Some(tx) => tx.send(value).is_ok(),
            None => false,
        }
    }

    pub fn close(&self, id: &str) {
        self.pending.lock().unwrap().remove(id);
    }
}

pub struct Shared {
    pub settings: Mutex<crate::settings::Store>,
    /// The pets' live state for the dashboard (see `status()` in crew.ts).
    pub status: Mutex<serde_json::Value>,
    /// crew.json as the page last saved it.
    pub crew: Mutex<serde_json::Value>,
    pub journal: crate::journal::Journal,
    pub replies: Replies,
    /// Per-install secret the MCP shim must send.
    pub token: String,
    pub reminders: crate::reminders::Reminders,
    pub notes: crate::notes::Notes,
    pub permissions: Permissions,
    pub codex: tokio::sync::Mutex<Option<std::sync::Arc<crate::codex::Codex>>>,
    /// Where each agent session runs, for "Open session".
    pub hosts: crate::sessions::Hosts,
    /// "claude:<session>" keys the user gave full access; the overlay owns the list and mirrors
    /// it here so those sessions' requests reach the companion even with a terminal in front.
    pub full_access: Mutex<std::collections::HashSet<String>>,
}

pub fn clip(text: &str, max: usize) -> String {
    let text = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if text.chars().count() <= max {
        return text;
    }
    let cut: String = text.chars().take(max.saturating_sub(1)).collect();
    format!("{}…", cut.trim_end())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn project_root_finds_the_repository() {
        let repo = std::env::temp_dir().join(format!("sidefolk-root-{}", std::process::id()));
        let deep = repo.join("src/app");
        std::fs::create_dir_all(&deep).unwrap();
        std::fs::create_dir_all(repo.join(".git")).unwrap();
        assert_eq!(project_root(deep.to_str().unwrap()), repo.display().to_string());
        assert_eq!(project_root(""), "");
        std::fs::remove_dir_all(repo).unwrap();
    }
}
