//! Persistent daily-driver preferences. Mutations commit to disk before replacing memory.
use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::{self, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
};
use tauri::{AppHandle, Manager};

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct Settings {
    pub pet_x: Option<f64>,
    pub display: Option<String>,
    pub hidden: bool,
    pub shortcut: String,
    /// system | light | dark. System follows macOS while running.
    pub theme: String,
    pub sleep_after_secs: u64,
    pub pet_answers_permissions: bool,
    /// Keep the overlay out of screenshots, recordings and screen sharing. Off by default: macOS
    /// then also blanks the overlay window in Mission Control: a dark patch around the companions
    /// (the window used to cover the screen, which turned every desktop's preview black).
    pub hide_in_recordings: bool,
    /// The one-time switch-off of `hide_in_recordings` (it used to be on by default) has run.
    /// Missing in older files, so it reads as false there and the switch-off runs once.
    #[serde(default)]
    pub recordings_reset: bool,
    /// The first-run card has been answered.
    pub onboarded: bool,
    /// small | medium | large.
    pub pet_size: String,
    /// Less wandering around (also on when macOS asks for reduced motion).
    pub calm: bool,
    pub large_text: bool,
    /// Say a meeting is coming, from the macOS calendars (off until the user turns it on).
    pub calendar_heads_up: bool,
    /// How many minutes before a meeting.
    pub calendar_lead_mins: u64,
    /// Babble and little sounds.
    pub sounds: bool,
    /// 0..=100
    pub volume: u8,
    /// A menu-bar-only app (no Dock icon, not in ⌘Tab).
    pub hide_from_dock: bool,
    /// Settings → Labs (docs/V1.md F-10, F-17): `$` commands and starting sessions, off by default.
    pub labs_commands: bool,
    pub labs_sessions: bool,
    /// The terminal sessions and commands open in: auto | terminal | iterm | ghostty | wezterm |
    /// kitty | alacritty.
    pub terminal: String,
}
impl Default for Settings {
    fn default() -> Self {
        Self {
            theme: "system".into(),
            pet_x: None,
            display: None,
            hidden: false,
            shortcut: "CommandOrControl+Shift+Space".into(),
            sleep_after_secs: 120,
            pet_answers_permissions: true,
            hide_in_recordings: false,
            recordings_reset: true,
            onboarded: false,
            pet_size: "medium".into(),
            calm: false,
            large_text: false,
            calendar_heads_up: false,
            calendar_lead_mins: 5,
            sounds: true,
            volume: 60,
            terminal: "auto".into(),
            labs_commands: false,
            labs_sessions: false,
            hide_from_dock: false,
        }
    }
}

pub fn data_dir(app: &AppHandle) -> tauri::Result<PathBuf> {
    match std::env::var_os("SIDEFOLK_DATA_DIR") {
        Some(path) => Ok(path.into()),
        None => app.path().app_data_dir(),
    }
}

pub struct Store {
    pub dir: PathBuf,
    pub value: Settings,
    /// The file couldn't be read or set aside, so nothing may be written over it (store.rs).
    blocked: bool,
}
impl Store {
    /// Never fails: a damaged settings file is set aside and the defaults load (docs/V1.md V1-S6).
    pub fn load(dir: PathBuf, problems: &crate::store::Problems) -> Self {
        let path = dir.join("settings.json");
        let loaded = crate::store::load::<Settings>(&path, 1, serde_json::Value::is_object, |_, data| data);
        problems.note(&path, &loaded);
        let blocked = matches!(loaded, crate::store::Loaded::Corrupt { kept: None, .. });
        let mut store = Self { dir, value: loaded.or_default(), blocked };
        // Older installs had it on without asking, which blacked out Mission Control; turn it
        // off once, and leave it alone from then on.
        if !store.value.recordings_reset
            && let Err(error) = store.update(|s| {
                s.hide_in_recordings = false;
                s.recordings_reset = true;
            })
        {
            eprintln!("sidefolk: settings not saved: {error}");
        }
        store
    }
    pub fn update(&mut self, change: impl FnOnce(&mut Settings)) -> io::Result<()> {
        let mut next = self.value.clone();
        change(&mut next);
        if next == self.value {
            return Ok(());
        }
        if self.blocked {
            return Err(io::Error::other("Your settings file couldn't be read, so I won't write over it."));
        }
        crate::store::save(&self.dir.join("settings.json"), 1, &next)?;
        self.value = next;
        Ok(())
    }
}

/// A private, unique sibling keeps partial writes out of both preferences and agent configs.
pub fn atomic_write(path: &Path, bytes: &[u8]) -> io::Result<()> {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let parent = path
        .parent()
        .ok_or_else(|| io::Error::other("Missing parent directory"))?;
    fs::create_dir_all(parent)?;
    let temp = parent.join(format!(
        ".sidefolk-{}-{}.tmp",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    let result = (|| {
        let mut options = fs::OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(&temp)?;
        if let Ok(metadata) = fs::metadata(path) {
            file.set_permissions(metadata.permissions())?;
        }
        file.write_all(bytes)?;
        file.sync_all()?;
        fs::rename(&temp, path)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn missing_fields_keep_defaults() {
        let value: Settings = serde_json::from_str(r#"{"hidden":true}"#).unwrap();
        assert!(value.hidden && value.pet_answers_permissions && !value.hide_in_recordings);
        assert_eq!(value.sleep_after_secs, 120);
        assert_eq!(value.shortcut, Settings::default().shortcut);
        assert_eq!(value.theme, "system");
    }
    #[test]
    fn old_installs_stop_blanking_mission_control_once() {
        let dir = std::env::temp_dir().join(format!("sidefolk-settings-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("settings.json"), r#"{"hide_in_recordings":true}"#).unwrap();
        let mut store = Store::load(dir.clone(), &Default::default());
        assert!(!store.value.hide_in_recordings && store.value.recordings_reset);
        store.update(|s| s.hide_in_recordings = true).unwrap();
        assert!(Store::load(dir.clone(), &Default::default()).value.hide_in_recordings);
        fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn damaged_settings_load_defaults_and_are_kept() {
        let dir = std::env::temp_dir().join(format!("sidefolk-settings-bad-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("settings.json"), b"{ \"theme\": ").unwrap();
        let problems = crate::store::Problems::default();
        let store = Store::load(dir.clone(), &problems);
        assert_eq!(store.value, Settings::default());
        assert_eq!(problems.list()[0].file, "settings.json");
        fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn saves_and_reloads() {
        let dir = std::env::temp_dir().join(format!("sidefolk-store-{}", std::process::id()));
        let mut store = Store::load(dir.clone(), &Default::default());
        store.update(|s| { s.pet_x = Some(321.0); s.theme = "dark".into(); }).unwrap();
        assert_eq!(Store::load(dir.clone(), &Default::default()).value.theme, "dark");
        assert_eq!(Store::load(dir.clone(), &Default::default()).value.pet_x, Some(321.0));
        fs::remove_dir_all(dir).unwrap();
    }
}
