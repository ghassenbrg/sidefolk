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
    pub sleep_after_secs: u64,
    pub pet_answers_permissions: bool,
    /// Keep the overlay out of screenshots, recordings and screen sharing: crew pets show
    /// project names.
    pub hide_in_recordings: bool,
    /// The first-run card has been answered.
    pub onboarded: bool,
    /// small | medium | large.
    pub pet_size: String,
    /// Less wandering around (also on when macOS asks for reduced motion).
    pub calm: bool,
    pub large_text: bool,
    /// Babble and little sounds.
    pub sounds: bool,
    /// 0..=100
    pub volume: u8,
    /// Read lines aloud with a macOS voice instead of babbling.
    pub speak: bool,
    /// A `say` voice name; empty for the system voice.
    pub voice: String,
    /// Where "Open session" continues a session: auto | terminal | iterm | ghostty.
    pub terminal: String,
}
impl Default for Settings {
    fn default() -> Self {
        Self {
            pet_x: None,
            display: None,
            hidden: false,
            shortcut: "CommandOrControl+Shift+Space".into(),
            sleep_after_secs: 120,
            pet_answers_permissions: true,
            hide_in_recordings: true,
            onboarded: false,
            pet_size: "medium".into(),
            calm: false,
            large_text: false,
            sounds: true,
            volume: 60,
            speak: false,
            voice: String::new(),
            terminal: "auto".into(),
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
}
impl Store {
    pub fn load(dir: PathBuf) -> io::Result<Self> {
        let value = match fs::read(dir.join("settings.json")) {
            Ok(bytes) => serde_json::from_slice(&bytes)?,
            Err(e) if e.kind() == io::ErrorKind::NotFound => Settings::default(),
            Err(e) => return Err(e),
        };
        Ok(Self { dir, value })
    }
    pub fn update(&mut self, change: impl FnOnce(&mut Settings)) -> io::Result<()> {
        let mut next = self.value.clone();
        change(&mut next);
        if next == self.value {
            return Ok(());
        }
        atomic_write(
            &self.dir.join("settings.json"),
            &serde_json::to_vec_pretty(&next)?,
        )?;
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
        assert!(value.hidden && value.pet_answers_permissions && value.hide_in_recordings);
        assert_eq!(value.sleep_after_secs, 120);
        assert_eq!(value.shortcut, Settings::default().shortcut);
    }
    #[test]
    fn saves_and_reloads() {
        let dir = std::env::temp_dir().join(format!("sidefolk-store-{}", std::process::id()));
        let mut store = Store::load(dir.clone()).unwrap();
        store.update(|s| s.pet_x = Some(321.0)).unwrap();
        assert_eq!(Store::load(dir.clone()).unwrap().value.pet_x, Some(321.0));
        fs::remove_dir_all(dir).unwrap();
    }
}
