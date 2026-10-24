//! "Open session": takes the user from a pet back to the agent session it speaks for.
//!
//! A live Claude Code session is brought to the front where it runs (Ghostty, Terminal, iTerm,
//! VS Code, the Claude app), on its own tab in Terminal and iTerm. A session that has ended,
//! runs nowhere visible (tmux, ssh) or is a Codex thread Sidefolk started in the background
//! continues in a new terminal window with `claude --resume` or `codex resume`.
//!
//! Where a session runs is found once per session: the hook server knows the TCP port Claude
//! Code connected from, `lsof` names the process that owns it, and the process tree leads up
//! to the app hosting it.
use std::{
    collections::{HashMap, HashSet},
    path::{Path, PathBuf},
    process::Command,
    sync::Mutex,
};

use serde::Serialize;
use tauri::{AppHandle, Manager, State};

use crate::bus::Shared;

#[derive(Clone, Debug, PartialEq)]
pub struct Host {
    pub pid: u32,
    /// The outermost .app the session runs in; `None` for tmux, ssh and other detached shells.
    pub app: Option<PathBuf>,
    /// `/dev/ttys004`, to pick the right tab in Terminal or iTerm.
    pub tty: Option<String>,
}

#[derive(Default)]
pub struct Hosts {
    known: Mutex<HashMap<String, Host>>,
    looking: Mutex<HashSet<String>>,
}

impl Hosts {
    pub fn get(&self, key: &str) -> Option<Host> {
        self.known.lock().unwrap().get(key).cloned()
    }

    /// Finds where a Claude session runs from the port its hook request came from, once.
    pub fn locate_claude(&self, app: &AppHandle, session: &str, peer_port: u16) {
        if session.is_empty() {
            return;
        }
        let key = format!("claude:{session}");
        if self.known.lock().unwrap().contains_key(&key) || !self.looking.lock().unwrap().insert(key.clone()) {
            return;
        }
        let app = app.clone();
        tauri::async_runtime::spawn_blocking(move || {
            let host = owner_of_port(peer_port).and_then(host_of);
            let hosts = &app.state::<std::sync::Arc<Shared>>().hosts;
            if let Some(host) = host {
                if cfg!(debug_assertions) {
                    eprintln!("sidefolk: {key} runs in {:?} {:?}", host.app, host.tty);
                }
                hosts.known.lock().unwrap().insert(key.clone(), host);
            }
            hosts.looking.lock().unwrap().remove(&key);
        });
    }
}

/// The process (other than Sidefolk) with a TCP connection from this local port.
fn owner_of_port(port: u16) -> Option<u32> {
    let out = Command::new("/usr/sbin/lsof")
        .args(["-nP", "-t", &format!("-iTCP@127.0.0.1:{port}")])
        .output()
        .ok()?;
    let me = std::process::id();
    String::from_utf8_lossy(&out.stdout).lines().filter_map(|l| l.trim().parse().ok()).find(|&pid| pid != me)
}

type Process = (u32, Option<String>, String); // parent, tty, executable

fn processes() -> HashMap<u32, Process> {
    let Ok(out) = Command::new("/bin/ps").args(["-axo", "pid=,ppid=,tty=,comm="]).output() else {
        return HashMap::new();
    };
    parse_ps(&String::from_utf8_lossy(&out.stdout))
}

fn parse_ps(listing: &str) -> HashMap<u32, Process> {
    listing
        .lines()
        .filter_map(|line| {
            let mut parts = line.split_whitespace();
            let pid = parts.next()?.parse().ok()?;
            let ppid = parts.next()?.parse().ok()?;
            let tty = parts.next()?;
            // The executable path may contain spaces; it is the rest of the line.
            let comm = parts.collect::<Vec<_>>().join(" ");
            let tty = (tty != "??").then(|| format!("/dev/{tty}"));
            Some((pid, (ppid, tty, comm)))
        })
        .collect()
}

/// The app bundle an executable belongs to: the outermost `.app` in its path.
fn bundle_of(executable: &str) -> Option<PathBuf> {
    let end = executable.find(".app/")?;
    let bundle = PathBuf::from(&executable[..end + 4]);
    // Claude Code ships its CLI in a lowercase claude.app inside its version directory.
    // Launching that bundle opens no window; keep walking to Terminal or Claude desktop.
    if bundle.file_name().is_some_and(|name| name == "claude.app") { return None; }
    Some(bundle)
}

fn host_of(pid: u32) -> Option<Host> {
    walk(pid, &processes())
}

fn walk(pid: u32, table: &HashMap<u32, Process>) -> Option<Host> {
    let (_, tty, _) = table.get(&pid)?;
    let mut current = pid;
    for _ in 0..32 {
        let (parent, _, comm) = table.get(&current)?;
        if let Some(app) = bundle_of(comm) {
            return Some(Host { pid, app: Some(app), tty: tty.clone() });
        }
        if *parent <= 1 {
            break;
        }
        current = *parent;
    }
    Some(Host { pid, app: None, tty: tty.clone() })
}

fn alive(pid: u32) -> bool {
    Command::new("/bin/ps").args(["-p", &pid.to_string()]).output().is_ok_and(|o| o.status.success())
}

/// Shell single quotes.
fn quote(text: &str) -> String {
    format!("'{}'", text.replace('\'', "'\\''"))
}

/// AppleScript double-quoted string.
fn apple(text: &str) -> String {
    format!("\"{}\"", text.replace('\\', "\\\\").replace('"', "\\\""))
}

pub(crate) fn osascript(script: &str) -> bool {
    Command::new("/usr/bin/osascript").args(["-e", script]).output().is_ok_and(|o| o.status.success())
}

/// A successful script can still mean no matching tab. Only report a selected tab on true.
fn select_tab(script: &str) -> bool {
    Command::new("/usr/bin/osascript").args(["-e", script]).output()
        .is_ok_and(|out| out.status.success() && String::from_utf8_lossy(&out.stdout).trim() == "true")
}

fn app_name(app: &Path) -> String {
    app.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_else(|| "the app".into())
}

/// Brings a live session's window forward; Terminal and iTerm also switch to its tab.
fn focus(host: &Host) -> Result<String, String> {
    let app = host.app.as_ref().ok_or("This session runs outside an app window.")?;
    let name = app_name(app);
    if let Some(tty) = &host.tty {
        let tty = apple(tty);
        // Needs the Automation permission once; without it the app still comes forward below.
        let picked = match name.as_str() {
            "Terminal" => select_tab(&format!(
                "tell application \"Terminal\"\nrepeat with w in windows\nrepeat with t in tabs of w\nif tty of t is {tty} then\nset selected of t to true\nset index of w to 1\nactivate\nreturn true\nend if\nend repeat\nend repeat\nend tell\nreturn false"
            )),
            "iTerm" | "iTerm2" => select_tab(&format!(
                "tell application \"iTerm2\"\nrepeat with w in windows\nrepeat with t in tabs of w\nrepeat with s in sessions of t\nif tty of s is {tty} then\nselect w\nselect t\nselect s\nactivate\nreturn true\nend if\nend repeat\nend repeat\nend repeat\nend tell\nreturn false"
            )),
            _ => false,
        };
        if picked {
            return Ok(format!("Opened in {name}."));
        }
    }
    let status = Command::new("/usr/bin/open").arg("-a").arg(app).status().map_err(|e| e.to_string())?;
    if !status.success() { return Err(format!("macOS couldn't open {name}.")); }
    Ok(format!("Opened {name}. Select your session in its window."))
}

const TERMINALS: [(&str, &str); 3] =
    [("terminal", "/System/Applications/Utilities/Terminal.app"), ("iterm", "/Applications/iTerm.app"), ("ghostty", "/Applications/Ghostty.app")];

pub(crate) fn terminal_for(choice: &str, recent: Option<&Path>) -> &'static str {
    let installed = |key: &str| TERMINALS.iter().any(|(k, path)| *k == key && Path::new(path).exists());
    if choice != "auto" && installed(choice) {
        return TERMINALS.iter().find(|(k, _)| *k == choice).unwrap().0;
    }
    // Auto: the terminal the user's sessions run in, else Terminal.
    let recent = recent.map(app_name).unwrap_or_default().to_lowercase();
    for key in ["ghostty", "iterm"] {
        if recent.starts_with(key) && installed(key) {
            return key;
        }
    }
    "terminal"
}

/// Starts `command` in `cwd` in a new terminal window, through the login shell so PATH
/// finds `claude` and `codex` as it does when the user types them. Returns the terminal's name.
pub(crate) fn run_in_terminal(terminal: &str, cwd: &str, command: &str) -> Result<&'static str, String> {
    let line = format!("cd {} && {command}", quote(cwd));
    match terminal {
        "iterm" => {
            let ok = osascript(&format!(
                "tell application \"iTerm2\"\nactivate\nset w to (create window with default profile)\ntell current session of w to write text {}\nend tell",
                apple(&line)
            ));
            ok.then_some("iTerm").ok_or_else(|| "iTerm didn't open. Allow Sidefolk to control iTerm in System Settings → Privacy & Security → Automation.".into())
        }
        "ghostty" => {
            let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".into());
            Command::new("/usr/bin/open")
                .args(["-na", "/Applications/Ghostty.app", "--args", &format!("--working-directory={cwd}"), "-e", &shell, "-lic"])
                .arg(format!("{command}; exec {shell} -l"))
                .status()
                .map_err(|e| e.to_string())?;
            Ok("Ghostty")
        }
        _ => {
            let ok = osascript(&format!("tell application \"Terminal\"\nactivate\ndo script {}\nend tell", apple(&line)));
            ok.then_some("Terminal").ok_or_else(|| "Terminal didn't open. Allow Sidefolk to control Terminal in System Settings → Privacy & Security → Automation.".into())
        }
    }
}

fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 100 && id.chars().all(|c| c.is_ascii_alphanumeric() || "-_.".contains(c))
}

#[derive(Serialize)]
pub struct Opened {
    /// "focused" (the live session came forward) or "resumed" (a new terminal window).
    how: &'static str,
    message: String,
}

/// Opens an agent session: the live one where it runs, otherwise a resumed one in a terminal.
#[tauri::command]
pub async fn open_session(
    shared: State<'_, std::sync::Arc<Shared>>,
    source: String,
    session: String,
    cwd: String,
    resume: Option<bool>,
) -> Result<Opened, String> {
    if !valid_id(&session) {
        return Err("This session can't be opened (no session ID).".into());
    }
    let key = format!("{source}:{session}");
    let host = shared.hosts.get(&key);
    if resume != Some(true) {
        if let Some(host) = host.as_ref().filter(|h| h.app.is_some() && alive(h.pid)) {
            let host = host.clone();
            let message = tauri::async_runtime::spawn_blocking(move || focus(&host)).await.map_err(|e| e.to_string())??;
            return Ok(Opened { how: "focused", message });
        }
    }
    if !Path::new(&cwd).is_dir() {
        return Err(format!("The session's folder is gone: {cwd}"));
    }
    let command = match source.as_str() {
        "claude" => format!("claude --resume {session}"),
        "codex" => {
            if let Some(codex) = shared.codex.lock().await.as_ref() {
                if codex.is_busy(&session) {
                    return Err("Codex is still working on this in the background. Open it when it finishes, so it doesn't run twice.".into());
                }
            }
            format!("codex resume {session}")
        }
        _ => return Err("Only Claude Code and Codex sessions can be opened.".into()),
    };
    let terminal = chosen_terminal(&shared);
    let name = tauri::async_runtime::spawn_blocking(move || run_in_terminal(terminal, &cwd, &command)).await.map_err(|e| e.to_string())??;
    Ok(Opened { how: "resumed", message: format!("Continuing in {name}.") })
}

/// The terminal from Settings, or (automatic) the one the user's sessions run in.
pub(crate) fn chosen_terminal(shared: &Shared) -> &'static str {
    let choice = shared.settings.lock().unwrap().value.terminal.clone();
    let recent = shared.hosts.known.lock().unwrap().values().filter_map(|h| h.app.clone()).last();
    terminal_for(&choice, recent.as_deref())
}

/// Terminals installed on this Mac, for Settings.
#[tauri::command]
pub fn terminals() -> Vec<&'static str> {
    TERMINALS.iter().filter(|(_, path)| Path::new(path).exists()).map(|(k, _)| *k).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_the_app_hosting_a_session() {
        let table = parse_ps(
            "  1     0 ??       /sbin/launchd\n\
             500     1 ??       /Applications/Ghostty.app/Contents/MacOS/ghostty\n\
             501   500 ttys004  /usr/bin/login\n\
             502   501 ttys004  -zsh\n\
             503   502 ttys004  claude\n\
             600     1 ??       /Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)\n\
             601   600 ttys009  /bin/zsh\n\
             602   601 ttys009  node\n\
             700     1 ??       tmux\n\
             701   700 ttys011  claude\n",
        );
        let host = walk(503, &table).unwrap();
        assert_eq!(host.app.as_deref(), Some(Path::new("/Applications/Ghostty.app")));
        assert_eq!(host.tty.as_deref(), Some("/dev/ttys004"));
        assert_eq!(walk(602, &table).unwrap().app.as_deref(), Some(Path::new("/Applications/Visual Studio Code.app")));
        let detached = walk(701, &table).unwrap();
        assert_eq!((detached.app, detached.tty.as_deref()), (None, Some("/dev/ttys011")));
        assert!(walk(9999, &table).is_none());
    }

    #[test]
    fn skips_bundled_claude_cli_for_desktop_and_terminal_sessions() {
        let table = parse_ps("1 0 ?? /sbin/launchd\n10 1 ?? /Applications/Claude.app/Contents/MacOS/Claude\n11 10 ?? /Users/me/.local/share/claude/versions/1/claude.app/Contents/MacOS/claude\n20 1 ?? /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal\n21 20 ttys002 /bin/zsh\n22 21 ttys002 /Users/me/.local/share/claude/versions/1/claude.app/Contents/MacOS/claude\n30 1 ?? /Users/me/.local/share/claude/versions/1/claude.app/Contents/MacOS/claude");
        assert_eq!(walk(11, &table).unwrap().app.as_deref(), Some(Path::new("/Applications/Claude.app")));
        let terminal = walk(22, &table).unwrap();
        assert_eq!(terminal.app.as_deref(), Some(Path::new("/System/Applications/Utilities/Terminal.app")));
        assert_eq!(terminal.tty.as_deref(), Some("/dev/ttys002"));
        assert_eq!(walk(30, &table).unwrap().app, None);
        assert_eq!(bundle_of("/Applications/Claude.app/Contents/Resources/claude.app/Contents/MacOS/claude"), Some(PathBuf::from("/Applications/Claude.app")));
    }

    #[cfg(target_os = "macos")]
    #[test]
    #[ignore = "focuses a live Claude desktop session; set SIDEFOLK_TEST_SESSION_PID"]
    fn live_claude_desktop_host() {
        let pid = std::env::var("SIDEFOLK_TEST_SESSION_PID").unwrap().parse().unwrap();
        let host = host_of(pid).expect("live process");
        assert_eq!(host.app.as_deref(), Some(Path::new("/Applications/Claude.app")));
        assert!(focus(&host).unwrap().starts_with("Opened Claude."));
        std::thread::sleep(std::time::Duration::from_secs(1));
        let front = tauri_nspanel::objc2_app_kit::NSWorkspace::sharedWorkspace().frontmostApplication().unwrap();
        assert_eq!(front.bundleIdentifier().unwrap().to_string(), "com.anthropic.claudefordesktop");
    }

    #[test]
    fn quotes_paths_and_rejects_odd_ids() {
        assert_eq!(quote("/a b/it's"), "'/a b/it'\\''s'");
        assert_eq!(apple("say \"hi\" \\"), "\"say \\\"hi\\\" \\\\\"");
        assert!(valid_id("3f2a9c1e-77b0-4c1a-9d0e-0a1b2c3d4e5f"));
        assert!(!valid_id("x; rm -rf ~"));
        assert!(!valid_id(""));
    }
}
