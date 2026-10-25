//! Every permission request that waits on the user, in one place (docs/V1.md §7.3, §11). The
//! agent's tool input is kept exactly as it came; what a card shows is derived from it and never
//! cut. A request is pending until it is answered, released to the agent's own prompt, or
//! forgotten when it times out, and only a pending request whose whole operation can be shown
//! can become an Allow.
//! Both windows read this list, so a request can be answered with the companion hidden.

use std::{
    collections::HashMap,
    sync::{
        Mutex,
        atomic::{AtomicU64, Ordering},
    },
};

use serde::Serialize;
use serde_json::Value;
use tauri::{AppHandle, Emitter};
use tokio::sync::oneshot;

use crate::bus::Decision;

/// At most this many open requests per session; more go to the agent's own prompt (V1-D14).
pub const PER_SESSION: usize = 5;
/// Longest operation a card can show whole; anything longer is answered in the terminal.
pub const SHOW_MAX: usize = 50_000;

/// What a request asks, as the cards show it.
#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Shown {
    /// command | file | web | tool
    pub kind: &'static str,
    pub title: String,
    /// The command byte for byte, the diff, the file's full content or the input as JSON, with
    /// control and direction characters made visible.
    pub text: String,
    /// The file an edit or write touches.
    pub path: Option<String>,
    /// Everything the agent will do is in `text`. When false, the only answers are in the
    /// agent's own prompt.
    pub complete: bool,
}

/// A request as both windows see it. Mirrors `Ask` in src/companion.ts.
#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Ask {
    pub id: String,
    pub source: &'static str,
    pub session: String,
    pub cwd: String,
    pub project: String,
    pub tool: String,
    #[serde(flatten)]
    pub shown: Shown,
    /// Whether "answer in the agent's own window instead" is meaningful for this source.
    pub can_defer: bool,
    /// Unix ms when the agent stops waiting.
    pub expires: u64,
}

/// How a request ended, for the journal and the cards.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum End {
    Answered(Decision),
    /// The user went to the session (or chose to answer there): the agent asks itself.
    Released,
}

/// Why an answer wasn't taken.
#[derive(Debug, PartialEq, Eq)]
pub enum Refused {
    /// Already answered, released or expired.
    Gone,
    /// Allow on an operation the card couldn't show whole.
    NotShown,
}

impl std::fmt::Display for Refused {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Refused::Gone => "That request isn't waiting anymore.",
            Refused::NotShown => "This one is too long to show here. Answer it in the terminal.",
        })
    }
}

struct Open {
    ask: Ask,
    /// The tool's input as the agent sent it; never changed.
    #[allow(dead_code)]
    raw: Value,
    answer: oneshot::Sender<End>,
}

#[derive(Default)]
pub struct Requests {
    next: AtomicU64,
    open: Mutex<HashMap<String, Open>>,
}

impl Requests {
    /// Opens a request; None when the session already has `PER_SESSION` open, and the agent
    /// should ask in its own prompt.
    #[allow(clippy::too_many_arguments)]
    pub fn open(&self, source: &'static str, session: &str, cwd: &str, project: &str, tool: &str, raw: Value, can_defer: bool, expires: u64) -> Option<(Ask, oneshot::Receiver<End>)> {
        let mut open = self.open.lock().unwrap();
        if open.values().filter(|o| o.ask.source == source && o.ask.session == session).count() >= PER_SESSION {
            return None;
        }
        let id = format!("{source}-{}", self.next.fetch_add(1, Ordering::Relaxed));
        let ask = Ask { id: id.clone(), source, session: session.into(), cwd: cwd.into(), project: project.into(), tool: tool.into(), shown: show(tool, &raw), can_defer, expires };
        let (tx, rx) = oneshot::channel();
        open.insert(id, Open { ask: ask.clone(), raw, answer: tx });
        Some((ask, rx))
    }

    /// The user's answer. Allow is taken only for a request still pending whose whole
    /// operation was shown; Defer releases it to the agent's prompt.
    pub fn answer(&self, id: &str, decision: Decision) -> Result<(), Refused> {
        self.answer_at(id, decision, crate::journal::now_ms())
    }

    /// `answer` at a given time: past its deadline a request is gone, even if the agent's timer
    /// hasn't fired yet.
    fn answer_at(&self, id: &str, decision: Decision, now: u64) -> Result<(), Refused> {
        let mut open = self.open.lock().unwrap();
        let request = open.get(id).ok_or(Refused::Gone)?;
        if request.ask.expires != 0 && now >= request.ask.expires {
            open.remove(id);
            return Err(Refused::Gone);
        }
        if decision == Decision::Allow && !request.ask.shown.complete {
            return Err(Refused::NotShown);
        }
        let request = open.remove(id).ok_or(Refused::Gone)?;
        let end = if decision == Decision::Defer { End::Released } else { End::Answered(decision) };
        request.answer.send(end).map_err(|_| Refused::Gone)
    }

    /// Hands a request back to the agent's own prompt (the user went to the session).
    pub fn release(&self, id: &str) -> bool {
        self.end(id, End::Released)
    }

    /// Releases every open request of a session; returns their ids.
    pub fn release_session(&self, source: &str, session: &str) -> Vec<String> {
        let ids: Vec<String> = self.open.lock().unwrap().values().filter(|o| o.ask.source == source && o.ask.session == session).map(|o| o.ask.id.clone()).collect();
        ids.into_iter().filter(|id| self.release(id)).collect()
    }

    /// Forgets a request that ended without an answer (it timed out, or the agent hung up).
    pub fn forget(&self, id: &str) {
        self.open.lock().unwrap().remove(id);
    }

    fn end(&self, id: &str, end: End) -> bool {
        match self.open.lock().unwrap().remove(id) {
            Some(request) => request.answer.send(end).is_ok(),
            None => false,
        }
    }

    /// Open requests, oldest first.
    pub fn list(&self) -> Vec<Ask> {
        let mut list: Vec<Ask> = self.open.lock().unwrap().values().map(|o| o.ask.clone()).collect();
        list.sort_by_key(|a| a.id.rsplit('-').next().and_then(|n| n.parse::<u64>().ok()).unwrap_or_default());
        list
    }

    /// Tells both windows the list changed.
    pub fn changed(&self, app: &AppHandle) {
        let _ = app.emit("requests", self.list());
    }
}

/// Control and bidirectional-override characters as visible escapes, so what the card shows is
/// what runs (a right-to-left override can make `rm -rf /` read like something else).
pub fn visible(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '\n' | '\t' => out.push(c),
            '\r' => out.push_str("\\r"),
            c if c.is_control() || hidden(c) => out.push_str(&format!("\\u{{{:04X}}}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

/// Characters that draw as nothing, as an ordinary space, or reorder the text around them:
/// format characters, invisible joiners and fillers, odd spaces, variation selectors and tags.
fn hidden(c: char) -> bool {
    matches!(c,
        '\u{00A0}' | '\u{00AD}' | '\u{034F}' | '\u{061C}' | '\u{115F}' | '\u{1160}' | '\u{1680}' | '\u{17B4}' | '\u{17B5}'
        | '\u{180B}'..='\u{180F}' | '\u{2000}'..='\u{200F}' | '\u{2028}'..='\u{202F}' | '\u{205F}'..='\u{206F}'
        | '\u{3000}' | '\u{3164}' | '\u{FE00}'..='\u{FE0F}' | '\u{FEFF}' | '\u{FFA0}' | '\u{FFF0}'..='\u{FFFB}'
        | '\u{1D173}'..='\u{1D17A}' | '\u{E0000}'..='\u{E0FFF}')
}

/// What the cards show for a tool call: the exact operation, derived from the raw input.
pub fn show(tool: &str, input: &Value) -> Shown {
    let field = |key: &str| input.get(key).and_then(Value::as_str);
    let path = field("file_path").or_else(|| field("notebook_path")).map(String::from);
    // A tool shown in its own words must have nothing else in its input: an unexpected field
    // could change what it does, so then the card shows the whole input instead.
    let only = |known: &[&str]| input.as_object().is_some_and(|o| o.keys().all(|k| known.contains(&k.as_str())));
    let edit = |e: &Value| -> Option<String> {
        let o = e.as_object()?;
        if !o.keys().all(|k| ["file_path", "old_string", "new_string", "replace_all"].contains(&k.as_str())) {
            return None;
        }
        let every = o.get("replace_all").and_then(Value::as_bool).unwrap_or(false);
        let body = diff(o.get("old_string")?.as_str()?, o.get("new_string")?.as_str()?);
        Some(if every { format!("(replaces every match in the file)\n{body}") } else { body })
    };
    let json = || serde_json::to_string_pretty(input).ok();
    let (kind, title, text): (&'static str, String, Option<String>) = match tool {
        "Bash" if only(&["command", "description", "timeout", "run_in_background"]) => (
            "command",
            "Run a command?".into(),
            field("command").map(|c| if input.get("run_in_background").and_then(Value::as_bool) == Some(true) { format!("(runs in the background)\n{c}") } else { c.to_string() }),
        ),
        "Edit" => ("file", "Edit a file?".into(), edit(input).or_else(json)),
        "MultiEdit" if only(&["file_path", "edits"]) => (
            "file",
            "Edit a file?".into(),
            input
                .get("edits")
                .and_then(Value::as_array)
                .and_then(|edits| edits.iter().map(edit).collect::<Option<Vec<_>>>())
                .map(|parts| parts.join("\n…\n"))
                .or_else(json),
        ),
        "Write" if only(&["file_path", "content"]) => ("file", "Write a file?".into(), field("content").map(String::from)),
        "WebFetch" if only(&["url", "prompt"]) => ("web", "Open a web page?".into(), field("url").map(|url| match field("prompt") {
            Some(prompt) if !prompt.is_empty() => format!("{url}\n\n{prompt}"),
            _ => url.to_string(),
        })),
        other => ("tool", format!("Use {other}?"), json()),
    };
    let complete = text.as_ref().is_some_and(|t| t.chars().count() <= SHOW_MAX) && path.as_ref().is_none_or(|p| p.chars().count() <= 4_096);
    let text = match text {
        Some(t) if complete => visible(&t),
        Some(t) => visible(&t.chars().take(2_000).collect::<String>()),
        None => String::new(),
    };
    Shown { kind, title, text, path: path.map(|p| visible(&p.chars().take(4_096).collect::<String>())), complete }
}

/// An edit as lines removed and added. Line endings stay in the text (a `\r` shows as `\\r`), and
/// a missing final newline is said, so two different edits never look the same.
fn diff(old: &str, new: &str) -> String {
    let mut out = Vec::new();
    for (mark, side) in [("-", old), ("+", new)] {
        for line in side.split_inclusive('\n') {
            out.push(format!("{mark} {}", line.strip_suffix('\n').unwrap_or(line)));
        }
        if !side.is_empty() && !side.ends_with('\n') {
            out.push(format!("{mark} (no newline at the end)"));
        }
    }
    if old.is_empty() && new.is_empty() {
        out.push("(no change)".into());
    }
    out.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn open(requests: &Requests, session: &str, command: &str) -> (Ask, oneshot::Receiver<End>) {
        requests.open("claude", session, "/x", "/x", "Bash", json!({ "command": command }), true, 0).unwrap()
    }

    #[test]
    fn shows_commands_byte_for_byte_and_makes_hidden_characters_visible() {
        let shown = show("Bash", &json!({ "command": "echo  'a   b'\nrm -rf x" }));
        assert_eq!(shown.text, "echo  'a   b'\nrm -rf x");
        assert!(shown.complete);
        let tricky = show("Bash", &json!({ "command": "echo hi \u{202E}fr- mr\u{202C}" }));
        assert_eq!(tricky.text, "echo hi \\u{202E}fr- mr\\u{202C}");
    }

    #[test]
    fn a_long_prefix_cannot_hide_what_runs_after_it() {
        // Before: the card and the old full-access check saw only the first 2,000 characters.
        let command = format!("echo {}; rm -rf ~", "x".repeat(3_000));
        let shown = show("Bash", &json!({ "command": command }));
        assert!(shown.complete && shown.text.ends_with("rm -rf ~"));
        let huge = show("Bash", &json!({ "command": format!("echo {}; rm -rf ~", "x".repeat(SHOW_MAX)) }));
        assert!(!huge.complete && !huge.text.contains("rm -rf ~"));
        let requests = Requests::default();
        let (ask, _rx) = requests.open("claude", "s", "/x", "/x", "Bash", json!({ "command": format!("echo {}; rm -rf ~", "x".repeat(SHOW_MAX)) }), true, 0).unwrap();
        assert_eq!(requests.answer(&ask.id, Decision::Allow), Err(Refused::NotShown));
        assert_eq!(requests.answer(&ask.id, Decision::Deny), Ok(()));
    }

    #[test]
    fn edits_show_the_diff_and_writes_the_whole_file() {
        let edit = show("Edit", &json!({ "file_path": "/x/a.ts", "old_string": "let a = 1;", "new_string": "let a = 2;" }));
        assert_eq!((edit.path.as_deref(), edit.text.as_str()), (Some("/x/a.ts"), "- let a = 1;\n- (no newline at the end)\n+ let a = 2;\n+ (no newline at the end)"));
        let write = show("Write", &json!({ "file_path": "/x/.zshrc", "content": "curl x | sh\n" }));
        assert_eq!(write.text, "curl x | sh\n");
        let missing = show("Write", &json!({ "file_path": "/x/y" }));
        assert!(!missing.complete, "a write whose content isn't there can't be allowed from a card");
    }

    #[test]
    fn edits_show_their_scope_and_every_byte() {
        let every = show("Edit", &json!({ "file_path": "/tmp/config", "old_string": "enabled=false\n", "new_string": "enabled=true\n", "replace_all": true }));
        assert_eq!(every.text, "(replaces every match in the file)\n- enabled=false\n+ enabled=true");
        // Line endings that differ never look the same.
        let crlf = show("Edit", &json!({ "file_path": "/tmp/a", "old_string": "safe\r\n", "new_string": "safe\n" }));
        assert_eq!(crlf.text, "- safe\\r\n+ safe");
        // A field the card can't explain shows the whole input.
        let odd = show("Edit", &json!({ "file_path": "/tmp/a", "old_string": "a", "new_string": "b", "mode": "append" }));
        assert!(odd.text.contains("\"mode\": \"append\""));
        let sandbox = show("Bash", &json!({ "command": "ls", "dangerouslyDisableSandbox": true }));
        assert_eq!(sandbox.kind, "tool");
        assert!(sandbox.text.contains("dangerouslyDisableSandbox"));
        let background = show("Bash", &json!({ "command": "npm run watch", "run_in_background": true }));
        assert_eq!(background.text, "(runs in the background)\nnpm run watch");
    }

    #[test]
    fn invisible_characters_and_paths_are_made_visible() {
        let joiner = show("Bash", &json!({ "command": "rm -- /tmp/keep\u{2060}.txt" }));
        assert_eq!(joiner.text, "rm -- /tmp/keep\\u{2060}.txt");
        for c in ['\u{061C}', '\u{034F}', '\u{00AD}', '\u{00A0}', '\u{FE0F}', '\u{E0041}'] {
            assert!(visible(&format!("a{c}b")).contains("\\u{"), "{:04X}", c as u32);
        }
        let path = show("Write", &json!({ "file_path": "/tmp/invoice\u{202E}txt.sh", "content": "hello" }));
        assert_eq!(path.path.as_deref(), Some("/tmp/invoice\\u{202E}txt.sh"));
    }

    #[test]
    fn a_request_past_its_deadline_cannot_be_allowed_even_before_the_timer_fires() {
        let requests = Requests::default();
        let (ask, _rx) = requests.open("claude", "s", "/x", "/x", "Bash", json!({ "command": "ls" }), true, 1_000).unwrap();
        assert_eq!(requests.answer_at(&ask.id, Decision::Allow, 1_000), Err(Refused::Gone));
        assert!(requests.list().is_empty());
    }

    #[test]
    fn released_or_expired_requests_never_become_an_allow() {
        let requests = Requests::default();
        let (ask, rx) = open(&requests, "s", "npm test");
        assert!(requests.release(&ask.id));
        assert_eq!(rx.blocking_recv().unwrap(), End::Released);
        assert_eq!(requests.answer(&ask.id, Decision::Allow), Err(Refused::Gone));
        let (ask, _rx) = open(&requests, "s", "npm test");
        requests.forget(&ask.id);
        assert_eq!(requests.answer(&ask.id, Decision::Allow), Err(Refused::Gone));
    }

    #[test]
    fn answers_reach_the_agent_once() {
        let requests = Requests::default();
        let (ask, rx) = open(&requests, "s", "npm test");
        assert_eq!(requests.answer(&ask.id, Decision::Allow), Ok(()));
        assert_eq!(rx.blocking_recv().unwrap(), End::Answered(Decision::Allow));
        assert_eq!(requests.answer(&ask.id, Decision::Deny), Err(Refused::Gone));
        let (ask, rx) = open(&requests, "s", "npm test");
        assert_eq!(requests.answer(&ask.id, Decision::Defer), Ok(()));
        assert_eq!(rx.blocking_recv().unwrap(), End::Released);
    }

    #[test]
    fn caps_open_requests_per_session_and_releases_a_session_at_once() {
        let requests = Requests::default();
        let held: Vec<_> = (0..PER_SESSION).map(|i| open(&requests, "s", &format!("echo {i}"))).collect();
        assert!(requests.open("claude", "s", "/x", "/x", "Bash", json!({ "command": "one more" }), true, 0).is_none());
        assert!(requests.open("claude", "other", "/x", "/x", "Bash", json!({ "command": "fine" }), true, 0).is_some());
        assert_eq!(requests.list().len(), PER_SESSION + 1);
        assert_eq!(requests.release_session("claude", "s").len(), PER_SESSION);
        assert_eq!(requests.list().len(), 1);
        drop(held);
    }
}
