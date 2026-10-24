//! Quick actions: plain commands typed to the companion ("ls -la", "run npm test in api") run
//! in the user's terminal after they've seen the exact command and folder. Nothing here goes
//! through an AI tool (docs/PLAN-V2.md, section 6.4).
use std::{
    collections::BTreeSet,
    path::{Path, PathBuf},
    process::Command,
    sync::OnceLock,
};

use serde::Serialize;
use tauri::State;

use crate::bus::Shared;

const MAX_COMMAND: usize = 500;
/// Where people keep repositories; a folder named in "run … in api" is looked for here.
const ROOTS: [&str; 7] = ["git", "Git", "code", "Code", "Developer", "Projects", "src"];

fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"))
}

/// The user's PATH as their login shell sets it (the app itself starts with launchd's short one).
pub(crate) fn login_path() -> &'static str {
    static PATH: OnceLock<String> = OnceLock::new();
    PATH.get_or_init(|| {
        let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".into());
        Command::new(shell)
            .args(["-lic", "printf %s \"$PATH\""])
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .map(|p| p.lines().last().unwrap_or_default().to_string())
            .filter(|p| !p.is_empty())
            .unwrap_or_else(|| "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin".into())
    })
}

/// Every command name on the user's PATH, so the companion can tell `ls -la` from a sentence
/// without asking anyone.
#[tauri::command]
pub async fn path_commands() -> Vec<String> {
    tauri::async_runtime::spawn_blocking(|| {
        let mut names = BTreeSet::new();
        for dir in login_path().split(':') {
            let Ok(entries) = std::fs::read_dir(dir) else { continue };
            for entry in entries.flatten() {
                if let Some(name) = entry.file_name().to_str() {
                    if !name.starts_with('.') && name.len() <= 40 {
                        names.insert(name.to_string());
                    }
                }
            }
        }
        names.into_iter().collect()
    })
    .await
    .unwrap_or_default()
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
