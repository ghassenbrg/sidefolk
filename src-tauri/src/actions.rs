//! Quick actions: `$` commands typed to the companion ("$ npm test in api", Settings → Labs) run
//! in the user's terminal after they've seen the exact command and folder, and "open …" opens a
//! folder, app or web address. Nothing here goes through an AI tool (docs/V1.md F-10, F-12).
use std::{
    path::{Path, PathBuf},
    process::Command,
};

use serde::Serialize;
use tauri::State;

use crate::bus::Shared;

/// A native folder chooser keeps creating a session usable without typing paths.
#[tauri::command]
pub async fn choose_project_folder(app: tauri::AppHandle) -> Result<Option<String>, String> {
    use tauri_plugin_dialog::DialogExt;
    let (sender, receiver) = tokio::sync::oneshot::channel();
    app.dialog().file().set_title("Choose a project folder").pick_folder(move |path| { let _ = sender.send(path); });
    receiver.await.map_err(|e| e.to_string())?.map(|path| {
        path.into_path().map(|p| p.to_string_lossy().into_owned()).map_err(|e| e.to_string())
    }).transpose()
}

const MAX_COMMAND: usize = 500;
/// Where people keep repositories; a folder named in "run … in api" is looked for here.
const ROOTS: [&str; 7] = ["git", "Git", "code", "Code", "Developer", "Projects", "src"];

fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"))
}

/// "~", "~/git/api", "/tmp" or a bare name ("api") found under the usual repository folders.
fn resolve(folder: &str) -> Option<PathBuf> {
    let folder = folder.trim().trim_end_matches('/');
    let home = home();
    let path = if folder.is_empty() || folder == "~" {
        home.clone()
    } else if let Some(rest) = folder.strip_prefix("~/") {
        home.join(rest)
    } else if folder.starts_with('/') {
        PathBuf::from(folder)
    } else if folder.contains('/') || folder.starts_with('.') {
        return None;
    } else {
        let mut candidates = vec![home.join(folder)];
        candidates.extend(ROOTS.iter().map(|root| home.join(root).join(folder)));
        return candidates.into_iter().find(|p| p.is_dir());
    };
    path.is_dir().then_some(path)
}

fn display(path: &Path) -> String {
    let home = home();
    match path.strip_prefix(&home) {
        Ok(rest) if rest.as_os_str().is_empty() => "~".into(),
        Ok(rest) => format!("~/{}", rest.display()),
        Err(_) => path.display().to_string(),
    }
}

#[derive(Serialize)]
pub struct Folder {
    path: String,
    /// "~/git/api", for showing.
    label: String,
}

/// The folder a command would run in, so the confirmation can show it before anything runs.
#[tauri::command]
pub fn resolve_folder(folder: Option<String>) -> Result<Folder, String> {
    let wanted = folder.unwrap_or_default();
    let path = resolve(&wanted).ok_or_else(|| format!("I can't find a folder called {wanted}."))?;
    Ok(Folder { label: display(&path), path: path.to_string_lossy().into() })
}

/// Runs a command the user confirmed, in a new window of their terminal.
#[tauri::command]
pub async fn run_command(shared: State<'_, std::sync::Arc<Shared>>, command: String, cwd: String) -> Result<String, String> {
    let command = command.trim().to_string();
    if command.is_empty() || command.len() > MAX_COMMAND || command.contains(['\n', '\r']) {
        return Err("That command can't be run from here.".into());
    }
    if !Path::new(&cwd).is_dir() {
        return Err(format!("The folder is gone: {cwd}"));
    }
    let terminal = crate::sessions::chosen_terminal(&shared);
    let name = tauri::async_runtime::spawn_blocking(move || crate::sessions::run_in_terminal(terminal, &cwd, &command))
        .await
        .map_err(|e| e.to_string())??;
    Ok(format!("Running in {name}."))
}

/// Starts a new Claude Code or Codex session in a folder, in a new window of the user's terminal.
/// Full access maps to each tool's own unattended mode: Claude Code's auto mode (its classifier
/// still stops risky actions) and Codex without approvals but sandboxed to the workspace.
#[tauri::command]
pub async fn start_session(shared: State<'_, std::sync::Arc<Shared>>, agent: String, cwd: String, full_access: bool) -> Result<String, String> {
    let command = match (agent.as_str(), full_access) {
        ("claude", false) => "claude",
        ("claude", true) => "claude --permission-mode auto",
        ("codex", false) => "codex",
        ("codex", true) => "codex -a never -s workspace-write",
        _ => return Err("Sidefolk can start Claude Code or Codex sessions.".into()),
    };
    if !Path::new(&cwd).is_dir() {
        return Err(format!("The folder is gone: {cwd}"));
    }
    let terminal = crate::sessions::chosen_terminal(&shared);
    let name = tauri::async_runtime::spawn_blocking(move || crate::sessions::run_in_terminal(terminal, &cwd, command))
        .await
        .map_err(|e| e.to_string())??;
    let agent = if agent == "codex" { "Codex" } else { "Claude Code" };
    Ok(format!("Started {agent} in {name}{}.", if full_access { " with full access" } else { "" }))
}

/// Apps people name differently from their bundle name.
const APP_NAMES: [(&str, &str); 8] = [
    ("vs code", "Visual Studio Code"),
    ("vscode", "Visual Studio Code"),
    ("code", "Visual Studio Code"),
    ("cursor", "Cursor"),
    ("zed", "Zed"),
    ("xcode", "Xcode"),
    ("intellij", "IntelliJ IDEA"),
    ("sublime", "Sublime Text"),
];

fn open(args: &[&str]) -> Result<(), String> {
    let output = Command::new("/usr/bin/open").args(args).output().map_err(|e| e.to_string())?;
    if output.status.success() {
        Ok(())
    } else {
        let why = String::from_utf8_lossy(&output.stderr);
        Err(if why.contains("Unable to find application") { "That app isn't installed.".into() } else { why.lines().next().unwrap_or("It didn't open.").to_string() })
    }
}

/// A web address the user typed ("github.com/me/x", "https://…"); anything else is refused.
fn web_address(text: &str) -> Option<String> {
    let text = text.trim();
    let url = if text.starts_with("https://") || text.starts_with("http://") { text.to_string() } else { format!("https://{text}") };
    let host = url.split("://").nth(1)?.split(['/', '?', '#']).next()?;
    (host.contains('.') && !host.contains(' ') && !url.contains(char::is_whitespace)).then_some(url)
}

/// "open sidefolk in VS Code", "open a terminal in api", "open github.com/x", "open Slack".
/// Opening is harmless and visible, so it happens at once; the reply says what opened.
#[tauri::command]
pub async fn open_target(shared: State<'_, std::sync::Arc<Shared>>, target: String, app: Option<String>) -> Result<String, String> {
    let target = target.trim().to_string();
    if let Some(app) = app.filter(|a| !a.trim().is_empty()) {
        let wanted = app.trim().to_lowercase();
        let name = APP_NAMES.iter().find(|(k, _)| *k == wanted).map_or(app.trim(), |(_, v)| v).to_string();
        let folder = resolve(&target).ok_or_else(|| format!("I can't find a folder called {target}."))?;
        if wanted == "terminal" || wanted == "the terminal" {
            let terminal = crate::sessions::chosen_terminal(&shared);
            let cwd = folder.to_string_lossy().to_string();
            let used = tauri::async_runtime::spawn_blocking(move || crate::sessions::run_in_terminal(terminal, &cwd, "true")).await.map_err(|e| e.to_string())??;
            return Ok(format!("Opened {} in {used}.", display(&folder)));
        }
        if wanted == "finder" {
            open(&[&folder.to_string_lossy()])?;
            return Ok(format!("Opened {} in Finder.", display(&folder)));
        }
        open(&["-a", &name, &folder.to_string_lossy()])?;
        return Ok(format!("Opened {} in {name}.", display(&folder)));
    }
    if let Some(url) = web_address(&target).filter(|_| target.contains('.') && !target.contains(' ')) {
        open(&[&url])?;
        return Ok(format!("Opened {url}."));
    }
    if let Some(folder) = resolve(&target).filter(|_| target.starts_with('~') || target.starts_with('/')) {
        open(&[&folder.to_string_lossy()])?;
        return Ok(format!("Opened {} in Finder.", display(&folder)));
    }
    open(&["-a", &target])?;
    Ok(format!("Opened {target}."))
}

/// Asks macOS, while the user is reading why (setup, Settings), to let Sidefolk control their
/// terminal: needed to open a command or session in Terminal or iTerm and to pick a session's tab.
/// macOS shows its own prompt the first time; later calls just report the answer.
#[tauri::command]
pub async fn allow_terminal_control(shared: State<'_, std::sync::Arc<Shared>>) -> Result<String, String> {
    let (name, app) = match crate::sessions::chosen_terminal(&shared) {
        "ghostty" => return Ok("Ghostty opens sessions without extra permission.".into()),
        "iterm" => ("iTerm", "iTerm2"),
        _ => ("Terminal", "Terminal"),
    };
    let script = format!("tell application \"{app}\" to count windows");
    let ok = tauri::async_runtime::spawn_blocking(move || crate::sessions::osascript(&script)).await.map_err(|e| e.to_string())?;
    if ok {
        Ok(format!("Sidefolk can open sessions and commands in {name}."))
    } else {
        Err(format!("Not allowed yet. Turn on Sidefolk → {name} in System Settings → Privacy & Security → Automation."))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_web_addresses() {
        assert_eq!(web_address("github.com/me/x").as_deref(), Some("https://github.com/me/x"));
        assert_eq!(web_address("http://localhost.test:3000").as_deref(), Some("http://localhost.test:3000"));
        assert_eq!(web_address("Slack"), None);
        assert_eq!(web_address("javascript:alert(1)"), None);
        assert_eq!(web_address("file:///etc/passwd"), None);
    }

    #[test]
    fn resolves_home_paths_and_rejects_relative_ones() {
        let home = home();
        assert_eq!(resolve("~"), Some(home.clone()));
        assert_eq!(resolve(""), Some(home.clone()));
        assert_eq!(resolve("/tmp").map(|p| p.is_dir()), Some(true));
        assert_eq!(resolve("../etc"), None);
        assert_eq!(resolve("a/b"), None);
        assert_eq!(resolve("surely-no-such-folder-here"), None);
        assert_eq!(display(&home), "~");
        assert_eq!(display(&home.join("git/api")), "~/git/api");
    }
}
