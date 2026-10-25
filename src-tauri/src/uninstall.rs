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
    /// Explicit agent profile roots whose Sidefolk skills may be restored. Empty in tests unless temporary.
    pub skill_profiles: Vec<PathBuf>,
    pub codex_hooks: Option<PathBuf>,
    pub login_item: PathBuf,
}

impl Places {
    /// The real ones, for the app and `sidefolk uninstall`.
    pub fn of_this_mac(data_dir: PathBuf, claude_settings: PathBuf) -> Self {
        // Resolve real profile paths only here, never inside disconnect or its test helpers.
        // Empty/relative overrides remain explicit invalid paths: restore fails closed rather
        // than silently skipping an agent and allowing the data/backups to be deleted.
        let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
        let mut skill_profiles: Vec<PathBuf> = [("CLAUDE_CONFIG_DIR", ".claude"), ("CODEX_HOME", ".codex")]
            .into_iter().map(|(key, default)| std::env::var_os(key).map(PathBuf::from).unwrap_or_else(|| home.join(default))).collect();
        skill_profiles.dedup();
        let codex_hooks = Some(crate::codex_setup::target_in(&home, std::env::var_os("CODEX_HOME").map(PathBuf::from).as_deref()));
        Self { data_dir, claude_settings, agents: vec![Agent::Claude, Agent::Codex], skill_profiles, codex_hooks, login_item: login_item() }
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
    run_with_bin(places, delete_data, to_bin)
}

// Inject the Bin operation in tests so even a regression cannot reach the user's real Trash.
fn run_with_bin(places: &Places, delete_data: bool, bin: impl FnOnce(&Path) -> std::io::Result<PathBuf>) -> Outcome {
    let mut outcome = disconnect(places);
    let data_dir = places.data_dir.as_path();
    if delete_data && outcome.ok {
        match bin(data_dir) {
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

/// Everything but the data: hooks, tools, managed skills, login item.
pub fn disconnect(places: &Places) -> Outcome {
    let (data_dir, claude_settings) = (places.data_dir.as_path(), places.claude_settings.as_path());
    let mut outcome = Outcome { said: Vec::new(), ok: true };
    let failed = |outcome: &mut Outcome, line: String| {
        outcome.said.push(line);
        outcome.ok = false;
    };
    for profile in &places.skill_profiles {
        match crate::skill_setup::restore(profile) {
            Ok(restored) => {
                if !restored.restored.is_empty() {
                    outcome.said.push(format!("Restored Sidefolk skill files in {} (original backups are kept).", profile.display()));
                }
                for conflict in restored.conflicts {
                    failed(&mut outcome, format!("Couldn't restore a Sidefolk skill file: {conflict}"));
                }
            }
            Err(error) => failed(&mut outcome, format!("Couldn't restore Sidefolk's skill in {}: {error}", profile.display())),
        }
    }
    let backups = data_dir.join("backups");
    if let Some(path) = &places.codex_hooks {
        match crate::codex_setup::remove(path, data_dir) {
            Ok(result) if result.status == "disconnected" => outcome.said.push("Removed Sidefolk's Codex hooks (a backup is kept).".into()),
            Ok(_) => {}
            Err(error) => failed(&mut outcome, format!("Couldn't remove Sidefolk's Codex hooks: {error}")),
        }
    }
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
        eprintln!("Some steps didn't work; see above. Your data and backups were kept. Resolve the reported problems and retry.");
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
        let places = Places { data_dir: data.clone(), claude_settings: settings.clone(), agents: vec![], skill_profiles: vec![], codex_hooks: None, login_item: login.clone() };
        let outcome = run(&places, false);
        assert!(outcome.ok && outcome.said[0].starts_with("Removed Sidefolk's hooks"));
        assert!(!login.exists());
        assert_eq!(serde_json::from_slice::<serde_json::Value>(&std::fs::read(&settings).unwrap()).unwrap(), mine);
        assert!(data.exists() && outcome.said.last().unwrap().contains("still in"));
        // When a step fails, the data (and the backups in it) stays even when asked to go.
        std::fs::write(&settings, b"not json").unwrap();
        let outcome = run_with_bin(&places, true, |_| panic!("Failed uninstall must not move data"));
        assert!(!outcome.ok && data.exists() && outcome.said.last().unwrap().contains("Kept your data"));
        std::fs::remove_dir_all(dir).unwrap();
    }

    struct Temp(PathBuf);
    impl Temp {
        fn new() -> Self {
            static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
            let base = std::fs::canonicalize(std::env::temp_dir()).unwrap();
            let dir = base.join(format!("sidefolk-uninstall-skills-{}-{}-{}", std::process::id(), crate::journal::now_ms(), NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)));
            std::fs::create_dir(&dir).unwrap();
            Self(dir)
        }
        fn places(&self, skill_profiles: Vec<PathBuf>) -> Places {
            let data_dir = self.0.join("data");
            std::fs::create_dir_all(data_dir.join("backups")).unwrap();
            std::fs::write(data_dir.join("reminders.json"), b"keep reminders").unwrap();
            std::fs::write(data_dir.join("backups/config.bak"), b"keep config backup").unwrap();
            let claude_settings = self.0.join("settings.json");
            std::fs::write(&claude_settings, b"{}").unwrap();
            Places { data_dir, claude_settings, agents:vec![], skill_profiles, codex_hooks: None, login_item:self.0.join("Sidefolk.plist") }
        }
    }
    impl Drop for Temp { fn drop(&mut self) { let _ = std::fs::remove_dir_all(&self.0); } }
    fn install_skill(profile: &Path) -> crate::skill_setup::Outcome {
        crate::skill_setup::Plan::prepare(profile, crate::skill_setup::Resources {
            skill:"test Sidefolk skill", metadata:"test Sidefolk metadata",
        }).unwrap().install().unwrap()
    }
    fn no_bin(_: &Path) -> std::io::Result<PathBuf> { panic!("This uninstall must keep data; never access the user's Bin") }

    #[test]
    fn uninstall_restores_skills_in_explicit_profiles_and_preserves_unrelated_files() {
        let temp = Temp::new();
        let claude = temp.0.join("claude");
        let codex = temp.0.join("codex");
        let target = claude.join("skills/sidefolk");
        std::fs::create_dir_all(&target).unwrap();
        let original = b"user skill\r\n\xff\x00";
        std::fs::write(target.join("SKILL.md"), original).unwrap();
        std::fs::write(target.join("unrelated.txt"), b"keep notebook").unwrap();
        let installed = install_skill(&claude);
        install_skill(&codex);
        let places = temp.places(vec![claude.clone(), codex.clone()]);
        let outcome = run_with_bin(&places, false, no_bin);
        assert!(outcome.ok, "{:?}", outcome.said);
        assert_eq!(std::fs::read(target.join("SKILL.md")).unwrap(), original);
        assert!(!target.join("agents/openai.yaml").exists());
        assert!(!codex.join("skills/sidefolk/SKILL.md").exists());
        assert!(!codex.join("skills/sidefolk/agents/openai.yaml").exists());
        assert_eq!(std::fs::read(target.join("unrelated.txt")).unwrap(), b"keep notebook");
        assert_eq!(std::fs::read(&installed.backups[0]).unwrap(), original);
        assert!(places.data_dir.join("reminders.json").is_file());
        assert_eq!(outcome.said.iter().filter(|s| s.starts_with("Restored Sidefolk skill files")).count(), 2);
        // Restore is idempotent, and no new skill ownership is invented on retry.
        assert!(run_with_bin(&places, false, no_bin).ok);
    }

    #[test]
    fn skill_edit_conflict_fails_uninstall_and_keeps_data_backups_and_provenance() {
        let temp = Temp::new();
        let profile = temp.0.join("claude");
        let target = profile.join("skills/sidefolk");
        std::fs::create_dir_all(&target).unwrap();
        std::fs::write(target.join("SKILL.md"), b"original skill").unwrap();
        let installed = install_skill(&profile);
        std::fs::write(target.join("SKILL.md"), b"user edit").unwrap();
        let places = temp.places(vec![profile.clone()]);
        let outcome = run_with_bin(&places, true, no_bin);
        assert!(!outcome.ok);
        assert!(outcome.said.iter().any(|s| s.contains("Managed file was edited")));
        assert!(outcome.said.last().unwrap().contains("Kept your data"));
        assert_eq!(std::fs::read(target.join("SKILL.md")).unwrap(), b"user edit");
        assert_eq!(std::fs::read(&installed.backups[0]).unwrap(), b"original skill");
        assert_eq!(std::fs::read(places.data_dir.join("backups/config.bak")).unwrap(), b"keep config backup");
        assert!(places.data_dir.join("reminders.json").exists());
        let provenance = profile.join("sidefolk-skill-backups/manifest.json");
        let manifest: serde_json::Value = serde_json::from_slice(&std::fs::read(provenance).unwrap()).unwrap();
        assert_eq!(manifest["files"].as_array().unwrap().len(), 1);
        // The conflict can be resolved and retried without losing the initial original.
        std::fs::write(target.join("SKILL.md"), b"test Sidefolk skill").unwrap();
        assert!(run_with_bin(&places, false, no_bin).ok);
        assert_eq!(std::fs::read(target.join("SKILL.md")).unwrap(), b"original skill");
    }

    #[test]
    fn skill_provenance_error_fails_uninstall_without_deleting_data() {
        let temp = Temp::new();
        let profile = temp.0.join("codex");
        let target = profile.join("skills/sidefolk");
        std::fs::create_dir_all(&target).unwrap();
        std::fs::write(target.join("SKILL.md"), b"original skill").unwrap();
        let installed = install_skill(&profile);
        let provenance = profile.join("sidefolk-skill-backups/manifest.json");
        std::fs::write(&provenance, b"corrupt provenance").unwrap();
        let places = temp.places(vec![profile]);
        let outcome = run_with_bin(&places, true, no_bin);
        assert!(!outcome.ok);
        assert!(outcome.said.iter().any(|s| s.starts_with("Couldn't restore Sidefolk's skill")));
        assert_eq!(std::fs::read(&provenance).unwrap(), b"corrupt provenance");
        assert_eq!(std::fs::read(&installed.backups[0]).unwrap(), b"original skill");
        assert_eq!(std::fs::read(target.join("SKILL.md")).unwrap(), b"test Sidefolk skill");
        assert!(places.data_dir.join("backups/config.bak").exists());
        assert!(places.data_dir.join("reminders.json").exists());
        assert!(outcome.said.last().unwrap().contains("Kept your data"));
    }

}
