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

// ---------------------------------------------------------------- saved actions

/// A named action: a command run in a folder, or a link. Kept in <data>/actions.json.
#[derive(Serialize, serde::Deserialize, Clone, Debug, PartialEq)]
pub struct Saved {
    pub name: String,
    /// "command" or "link".
    pub kind: String,
    pub value: String,
    #[serde(default)]
    pub folder: String,
}

const MAX_SAVED: usize = 100;
/// A background run stops after this, so a forgotten watcher can't run forever.
const RUN_LIMIT: std::time::Duration = std::time::Duration::from_secs(600);

fn saved_path(shared: &Shared) -> PathBuf {
    shared.settings.lock().unwrap().dir.join("actions.json")
}

fn read_saved(shared: &Shared) -> Vec<Saved> {
    std::fs::read(saved_path(shared)).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

fn find_saved(shared: &Shared, name: &str) -> Option<Saved> {
    let want = name.trim().to_lowercase();
    read_saved(shared).into_iter().find(|a| a.name.to_lowercase() == want)
}

#[tauri::command]
pub fn list_actions(shared: State<'_, std::sync::Arc<Shared>>) -> Vec<Saved> {
    read_saved(&shared)
}

/// Saves (or replaces, by name) an action. Commands keep the folder they run in.
#[tauri::command]
pub fn save_action(shared: State<'_, std::sync::Arc<Shared>>, name: String, kind: String, value: String, folder: Option<String>) -> Result<Saved, String> {
    let name: String = name.split_whitespace().collect::<Vec<_>>().join(" ").chars().take(40).collect();
    let value = value.trim().to_string();
    if name.is_empty() || value.is_empty() || value.len() > MAX_COMMAND || value.contains(['\n', '\r']) {
        return Err("An action needs a name and a one-line command or link.".into());
    }
    let saved = match kind.as_str() {
        "command" => {
            let folder = resolve(folder.as_deref().unwrap_or_default()).ok_or("I can't find that folder.")?;
            Saved { name, kind, value, folder: folder.to_string_lossy().into() }
        }
        "link" => Saved { name, kind, value: web_address(&value).ok_or("That isn't a web address.")?, folder: String::new() },
        _ => return Err("An action is a command or a link.".into()),
    };
    let mut list: Vec<Saved> = read_saved(&shared).into_iter().filter(|a| a.name.to_lowercase() != saved.name.to_lowercase()).collect();
    if list.len() >= MAX_SAVED {
        return Err("That's a lot of actions. Remove some first.".into());
    }
    list.push(saved.clone());
    crate::settings::atomic_write(&saved_path(&shared), &serde_json::to_vec_pretty(&list).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
    Ok(saved)
}

#[tauri::command]
pub fn remove_action(shared: State<'_, std::sync::Arc<Shared>>, name: String) -> Result<(), String> {
    let list: Vec<Saved> = read_saved(&shared).into_iter().filter(|a| a.name.to_lowercase() != name.trim().to_lowercase()).collect();
    crate::settings::atomic_write(&saved_path(&shared), &serde_json::to_vec_pretty(&list).map_err(|e| e.to_string())?).map_err(|e| e.to_string())
}

#[derive(Serialize)]
pub struct Ran {
    ok: bool,
    message: String,
    /// A background run's output file, for "Show output".
    log: Option<String>,
}

/// Runs a saved action: a link opens; a command opens in the terminal (`background` false) or
/// runs quietly and reports done or failed with its output kept in <data>/logs/actions.
#[tauri::command]
pub async fn run_action(shared: State<'_, std::sync::Arc<Shared>>, name: String, background: Option<bool>) -> Result<Ran, String> {
    let action = find_saved(&shared, &name).ok_or_else(|| format!("There's no action called {name}."))?;
    if action.kind == "link" {
        open(&[&action.value])?;
        return Ok(Ran { ok: true, message: format!("Opened {}.", action.name), log: None });
    }
    if !Path::new(&action.folder).is_dir() {
        return Err(format!("The folder is gone: {}", action.folder));
    }
    if background != Some(true) {
        let terminal = crate::sessions::chosen_terminal(&shared);
        let (cwd, command) = (action.folder.clone(), action.value.clone());
        let used = tauri::async_runtime::spawn_blocking(move || crate::sessions::run_in_terminal(terminal, &cwd, &command)).await.map_err(|e| e.to_string())??;
        return Ok(Ran { ok: true, message: format!("Running {} in {used}.", action.name), log: None });
    }
    let logs = shared.settings.lock().unwrap().dir.join("logs").join("actions");
    std::fs::create_dir_all(&logs).map_err(|e| e.to_string())?;
    let log = logs.join(format!("{}.log", action.name.to_lowercase().replace(|c: char| !c.is_ascii_alphanumeric(), "-")));
    let file = std::fs::File::create(&log).map_err(|e| e.to_string())?;
    let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".into());
    let mut child = tokio::process::Command::new(shell)
        .args(["-lc", &action.value])
        .current_dir(&action.folder)
        .env("PATH", login_path())
        .stdin(std::process::Stdio::null())
        .stdout(file.try_clone().map_err(|e| e.to_string())?)
        .stderr(file)
        .kill_on_drop(true)
        .spawn()
        .map_err(|e| e.to_string())?;
    let log_text = log.to_string_lossy().to_string();
    match tokio::time::timeout(RUN_LIMIT, child.wait()).await {
        Ok(Ok(status)) if status.success() => Ok(Ran { ok: true, message: format!("{} finished.", action.name), log: Some(log_text) }),
        Ok(Ok(status)) => Ok(Ran { ok: false, message: format!("{} failed (exit code {}).", action.name, status.code().unwrap_or(-1)), log: Some(log_text) }),
        Ok(Err(e)) => Err(e.to_string()),
        Err(_) => Ok(Ran { ok: false, message: format!("{} was still running after 10 minutes, so I stopped it.", action.name), log: Some(log_text) }),
    }
}

/// Opens a background run's output in the default text editor.
#[tauri::command]
pub fn show_output(shared: State<'_, std::sync::Arc<Shared>>, log: String) -> Result<(), String> {
    let logs = shared.settings.lock().unwrap().dir.join("logs").join("actions");
    let path = PathBuf::from(&log);
    if path.parent() != Some(logs.as_path()) {
        return Err("That isn't an action's output.".into());
    }
    open(&["-t", &log])
}

/// Puts `sidefolk` on the PATH (/usr/local/bin, like VS Code's `code`), on the user's click; macOS
/// asks for an administrator password in its own dialog.
#[tauri::command]
pub async fn install_cli() -> Result<String, String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let exe = exe.to_string_lossy().to_string();
    if !exe.contains(".app/Contents/MacOS/") {
        return Err("Install the command from the Sidefolk app in Applications.".into());
    }
    let shell = format!("mkdir -p /usr/local/bin && ln -sf {} /usr/local/bin/sidefolk", crate::sessions::quote(&exe));
    let script = format!(
        "do shell script {} with prompt \"Sidefolk wants to add the sidefolk command to your terminal.\" with administrator privileges",
        crate::sessions::apple(&shell)
    );
    let ok = tauri::async_runtime::spawn_blocking(move || crate::sessions::osascript(&script)).await.map_err(|e| e.to_string())?;
    if ok {
        Ok("Installed. In a terminal, try: sidefolk here --name Backend".into())
    } else {
        Err("Not installed (cancelled or not allowed).".into())
    }
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
