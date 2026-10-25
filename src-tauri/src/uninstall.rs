//! Disconnect & uninstall (docs/V1.md V1-X2): removes only what Sidefolk added to the agents'
//! settings (with backups), turns off its login item, and keeps the user's data unless they ask
//! for it to go to the Bin. The same steps run from the window, the menu bar and, without the
//! app, from `sidefolk uninstall`. Dragging Sidefolk to the Bin is the user's last step.

use std::path::{Path, PathBuf};

use crate::mcp_setup::Agent;

/// Everything uninstalling touches, passed in so a test can point all of it at a temporary
/// folder: the user's real agent configs and login item are never reached by a test.
pub struct Places {
    pub data_dir: PathBuf,
    pub claude_settings: PathBuf,
    /// The agents whose MCP entries to remove through their own CLIs.
    pub agents: Vec<Agent>,
    pub login_item: PathBuf,
}

impl Places {
    /// The real ones, for the app and `sidefolk uninstall`.
    pub fn of_this_mac(data_dir: PathBuf, claude_settings: PathBuf) -> Self {
        Self { data_dir, claude_settings, agents: vec![Agent::Claude, Agent::Codex], login_item: login_item() }
    }
}

/// What uninstalling did, in plain words, and whether every step worked.
pub struct Outcome {
    pub said: Vec<String>,
    pub ok: bool,
}

/// Disconnects everything. `delete_data` moves the data folder to the Bin, only when every
/// step before it worked: the backups of the agents' settings are in there.
pub fn run(places: &Places, delete_data: bool) -> Outcome {
    let mut outcome = disconnect(places);
    let data_dir = places.data_dir.as_path();
    if delete_data && outcome.ok {
        match to_bin(data_dir) {
            Ok(at) => outcome.said.push(format!("Moved your Sidefolk data to the Bin ({}).", at.display())),
            Err(error) => {
                outcome.said.push(format!("Couldn't move your data to the Bin: {error}"));
                outcome.ok = false;
            }
        }
    } else {
        outcome.said.push(kept(data_dir, delete_data));
    }
    outcome
}

/// Why the data is still there.
pub fn kept(data_dir: &Path, asked_to_delete: bool) -> String {
    if asked_to_delete {
        format!("Kept your data in {}, because a step above didn't work; its backups are there.", data_dir.display())
    } else {
        format!("Your reminders, notes and backups are still in {}.", data_dir.display())
    }
}

/// Everything but the data: hooks, tools, login item.
pub fn disconnect(places: &Places) -> Outcome {
    let (data_dir, claude_settings) = (places.data_dir.as_path(), places.claude_settings.as_path());
    let mut outcome = Outcome { said: Vec::new(), ok: true };
    let failed = |outcome: &mut Outcome, line: String| {
        outcome.said.push(line);
        outcome.ok = false;
    };
    let backups = data_dir.join("backups");
    match crate::claude_setup::remove(claude_settings, data_dir) {
        Ok(Some(_)) => outcome.said.push("Removed Sidefolk's hooks from Claude Code (a backup is kept).".to_string()),
        Ok(None) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => failed(&mut outcome, format!("Couldn't change Claude Code's settings: {error}")),
    }
    for &agent in &places.agents {
        if agent.installed() {
            match crate::mcp_setup::run(agent, false, &backups) {
                Ok(_) => outcome.said.push(format!("Removed Sidefolk's tools from {}.", agent.name())),
                Err(error) => failed(&mut outcome, format!("Couldn't remove Sidefolk's tools from {}: {error}", agent.name())),
            }
        }
    }
    if places.login_item.exists() {
        match std::fs::remove_file(&places.login_item) {
            Ok(()) => outcome.said.push("Sidefolk no longer opens at login.".into()),
            Err(error) => failed(&mut outcome, format!("Couldn't turn off opening at login: {error}")),
        }
    }
    outcome
}

/// The login item the autostart plugin writes (a LaunchAgent named after the app).
fn login_item() -> PathBuf {
    PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join("Library/LaunchAgents/Sidefolk.plist")
}

/// Into the user's Bin, where Finder can put it back; never deleted outright.
pub fn to_bin(data_dir: &Path) -> std::io::Result<PathBuf> {
    let bin = PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".Trash");
    let at = bin.join(format!("Sidefolk data {}", crate::journal::now_ms()));
    std::fs::rename(data_dir, &at)?;
    Ok(at)
}

/// `sidefolk uninstall [--delete-data]` in a terminal, with or without the app running.
pub fn run_cli(args: &[String]) -> i32 {
    let delete = args.iter().any(|a| a == "--delete-data");
    let data_dir = crate::mcp::shim_data_dir();
    // A running Sidefolk would write its data and hooks back; it uninstalls itself from its window.
    if std::os::unix::net::UnixStream::connect(crate::socket::path(&data_dir)).is_ok() {
        eprintln!("Sidefolk is running. Use Settings → Privacy & data → Disconnect & uninstall, or quit Sidefolk and run this again.");
        return 1;
    }
    let outcome = run(&Places::of_this_mac(data_dir, crate::claude_setup::default_target()), delete);
    for line in &outcome.said {
        println!("{line}");
    }
    if !outcome.ok {
        eprintln!("Some steps didn't work; see above. Nothing else was changed.");
        return 1;
    }
    println!("Last step: drag Sidefolk from Applications to the Bin.");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn removes_only_sidefolks_hooks_and_keeps_data_by_default() {
        let dir = std::env::temp_dir().join(format!("sidefolk-uninstall-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let settings = dir.join("settings.json");
        let mine = serde_json::json!({"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}]}});
        let with_ours = crate::claude_setup::install(mine.clone(), Path::new("/Applications/Sidefolk.app/Contents/MacOS/sidefolk"));
        std::fs::write(&settings, serde_json::to_vec(&with_ours).unwrap()).unwrap();
        let data = dir.join("data");
        std::fs::create_dir_all(&data).unwrap();
        // Only temporary paths: no agent CLI runs, and the real login item is out of reach.
        let login = dir.join("Sidefolk.plist");
        std::fs::write(&login, b"<plist/>").unwrap();
        let places = Places { data_dir: data.clone(), claude_settings: settings.clone(), agents: vec![], login_item: login.clone() };
        let outcome = run(&places, false);
        assert!(outcome.ok && outcome.said[0].starts_with("Removed Sidefolk's hooks"));
        assert!(!login.exists());
        assert_eq!(serde_json::from_slice::<serde_json::Value>(&std::fs::read(&settings).unwrap()).unwrap(), mine);
        assert!(data.exists() && outcome.said.last().unwrap().contains("still in"));
        // When a step fails, the data (and the backups in it) stays even when asked to go.
        std::fs::write(&settings, b"not json").unwrap();
        let outcome = run(&places, true);
        assert!(!outcome.ok && data.exists() && outcome.said.last().unwrap().contains("Kept your data"));
        std::fs::remove_dir_all(dir).unwrap();
    }
}
