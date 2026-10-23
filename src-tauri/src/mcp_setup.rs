//! Adds or removes the pet tools (mcp.rs) for Claude Code and Codex, only after a tray click
//! and a confirmation. Changes go through each agent's own `mcp add/remove` command; the config
//! file it edits is backed up byte for byte first. Status is read from that file directly.
use crate::{bus::Shared, settings::atomic_write};
use std::{
    fs, io,
    path::PathBuf,
    process::Command,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};
use tauri::{AppHandle, Manager};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Agent {
    Claude,
    Codex,
}

impl Agent {
    pub fn name(self) -> &'static str {
        match self {
            Agent::Claude => "Claude Code",
            Agent::Codex => "Codex",
        }
    }

    fn cli(self) -> &'static str {
        match self {
            Agent::Claude => "claude",
            Agent::Codex => "codex",
        }
    }

    /// The file the agent's `mcp add` edits (honoring the agents' own overrides).
    pub fn config(self) -> PathBuf {
        let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
        match self {
            Agent::Claude => std::env::var_os("CLAUDE_CONFIG_DIR")
                .map(|dir| PathBuf::from(dir).join(".claude.json"))
                .unwrap_or_else(|| home.join(".claude.json")),
            Agent::Codex => std::env::var_os("CODEX_HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|| home.join(".codex"))
                .join("config.toml"),
        }
    }

    pub fn installed(self) -> bool {
        let Ok(text) = fs::read_to_string(self.config()) else { return false };
        match self {
            Agent::Claude => serde_json::from_str::<serde_json::Value>(&text)
                .is_ok_and(|v| v["mcpServers"].get(crate::mcp::SERVER).is_some()),
            Agent::Codex => text.lines().any(|line| {
                let line = line.trim();
                line == "[mcp_servers.sidefolk]" || line == "[mcp_servers.\"sidefolk\"]"
            }),
        }
    }

    /// The agent CLI's arguments to add or remove the server.
    pub fn args(self, add: bool, exe: &str, data_dir: Option<&str>) -> Vec<String> {
        let mut args: Vec<String> = vec!["mcp".into(), if add { "add" } else { "remove" }.into()];
        if self == Agent::Claude {
            args.extend(["--scope".into(), "user".into()]);
        }
        args.push(crate::mcp::SERVER.into());
        if add {
            // An isolated data directory (development) must reach the shim too.
            if let Some(dir) = data_dir {
                args.push(if self == Agent::Claude { "-e" } else { "--env" }.into());
                args.push(format!("SIDEFOLK_DATA_DIR={dir}"));
            }
            args.extend(["--".into(), exe.into(), "--mcp".into()]);
        }
        args
    }
}

fn run(agent: Agent, add: bool, backups: &std::path::Path) -> io::Result<PathBuf> {
    let config = agent.config();
    let stamp = crate::journal::now_ms();
    let backup = backups.join(format!("{}-{stamp}.bak", agent.cli()));
    match fs::read(&config) {
        Ok(bytes) => atomic_write(&backup, &bytes)?,
        Err(e) if e.kind() == io::ErrorKind::NotFound => {}
        Err(e) => return Err(e),
    }
    let exe = std::env::current_exe()?.display().to_string();
    let data_dir = std::env::var("SIDEFOLK_DATA_DIR").ok();
    let output = Command::new(agent.cli())
        .args(agent.args(add, &exe, data_dir.as_deref()))
        .env("PATH", crate::codex::agent_path())
        // Started from inside a Claude Code session, the CLI would think it is nested.
        .env_remove("CLAUDECODE")
        .env_remove("CLAUDE_CODE_ENTRYPOINT")
        .output()
        .map_err(|e| io::Error::other(format!("Could not run `{}` ({e}). Is it installed?", agent.cli())))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(io::Error::other(format!("`{} mcp` failed: {}", agent.cli(), stderr.trim())));
    }
    Ok(backup)
}

#[derive(Default)]
pub struct McpSetupState {
    busy: AtomicBool,
}

pub fn confirm(app: &AppHandle, agent: Agent) {
    if app.state::<McpSetupState>().busy.swap(true, Ordering::SeqCst) {
        return;
    }
    let add = !agent.installed();
    let backups = app.state::<Arc<Shared>>().settings.lock().unwrap().dir.join("backups");
    let (title, change) = if add {
        (
            format!("Add pet tools to {}?", agent.name()),
            format!(
                "{} sessions get four tools that reach you through the pet: notify, ask, remind and presence. Each session's project decides which pet speaks.",
                agent.name()
            ),
        )
    } else {
        (format!("Remove pet tools from {}?", agent.name()), "Only Sidefolk's MCP server is removed.".into())
    };
    let message = format!(
        "{change}\n\nRuns `{} mcp {}` for your user. Applies to new sessions.\nA backup of {} is saved first in:\n{}",
        agent.cli(),
        if add { "add" } else { "remove" },
        agent.config().display(),
        backups.display()
    );
    let handle = app.clone();
    app.dialog()
        .message(message)
        .title(title)
        .buttons(MessageDialogButtons::OkCancelCustom(
            if add { "Add" } else { "Remove" }.into(),
            "Cancel".into(),
        ))
        .show(move |confirmed| {
            if !confirmed {
                handle.state::<McpSetupState>().busy.store(false, Ordering::SeqCst);
                return;
            }
            std::thread::spawn(move || {
                let result = run(agent, add, &backups);
                let app = handle.clone();
                let _ = handle.run_on_main_thread(move || {
                    app.state::<McpSetupState>().busy.store(false, Ordering::SeqCst);
                    let _ = crate::tray::refresh(&app);
                    match result {
                        Ok(backup) => eprintln!("sidefolk: {} pet tools changed; backup {}", agent.name(), backup.display()),
                        Err(error) => {
                            eprintln!("sidefolk: pet tools: {error}");
                            app.dialog()
                                .message(error.to_string())
                                .title("Pet tools")
                                .kind(MessageDialogKind::Error)
                                .show(|_| {});
                        }
                    }
                });
            });
        });
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn builds_cli_arguments() {
        assert_eq!(
            Agent::Claude.args(true, "/A/sidefolk", None),
            ["mcp", "add", "--scope", "user", "sidefolk", "--", "/A/sidefolk", "--mcp"]
        );
        assert_eq!(
            Agent::Codex.args(true, "/A/sidefolk", Some("/tmp/d")),
            ["mcp", "add", "sidefolk", "--env", "SIDEFOLK_DATA_DIR=/tmp/d", "--", "/A/sidefolk", "--mcp"]
        );
        assert_eq!(Agent::Claude.args(false, "x", None), ["mcp", "remove", "--scope", "user", "sidefolk"]);
        assert_eq!(Agent::Codex.args(false, "x", None), ["mcp", "remove", "sidefolk"]);
    }

    /// Runs the real CLIs against throwaway config folders:
    /// `cargo test agents_cli_round_trip -- --ignored --test-threads=1`
    #[test]
    #[ignore = "runs the claude and codex CLIs against temporary config folders"]
    fn agents_cli_round_trip() {
        let root = std::env::temp_dir().join(format!("sidefolk-mcp-setup-{}", std::process::id()));
        fs::create_dir_all(root.join("codex")).unwrap();
        // SAFETY: test-only, single-threaded (see the command above).
        unsafe {
            std::env::set_var("CLAUDE_CONFIG_DIR", root.join("claude"));
            std::env::set_var("CODEX_HOME", root.join("codex"));
        }
        for agent in [Agent::Claude, Agent::Codex] {
            assert!(!agent.installed(), "{agent:?} starts clean");
            run(agent, true, &root.join("backups")).unwrap();
            assert!(agent.installed(), "{agent:?} added");
            run(agent, false, &root.join("backups")).unwrap();
            assert!(!agent.installed(), "{agent:?} removed");
        }
        fs::remove_dir_all(root).unwrap();
    }
}
