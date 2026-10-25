//! Every JSON store goes through here (docs/V1.md §3). A missing file starts empty. A damaged or
//! unreadable one is set aside as `<name>.corrupt-<ms>` and never overwritten, and the app says
//! so. Each good load leaves `<name>.bak`, the copy "Restore last good copy" puts back. Files are
//! written as `{ "version": n, "data": … }`; files from before that are read as version 0.
use serde::{Serialize, de::DeserializeOwned};
use serde_json::{Value, json};
use std::{
    fs, io,
    path::{Path, PathBuf},
    sync::Mutex,
};

/// What loading a store found.
pub enum Loaded<T> {
    Missing,
    Ok(T),
    /// The data was unusable. `kept` is where its bytes are now; None when even moving it failed,
    /// and then nothing may be written over it.
    Corrupt { kept: Option<PathBuf>, error: String },
}

impl<T> Loaded<T> {
    /// The value, or the default when it was missing or damaged (damage is reported separately).
    pub fn or_default(self) -> T
    where
        T: Default,
    {
        match self {
            Loaded::Ok(value) => value,
            _ => T::default(),
        }
    }
}

/// A store that couldn't be read at launch, for the window's banner.
#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Problem {
    /// The file name, e.g. "reminders.json".
    pub file: String,
    /// Where the damaged bytes were moved; empty when they couldn't be moved.
    pub kept: String,
    pub error: String,
    /// A last good copy exists to restore.
    pub backup: bool,
}

/// Damaged stores found since launch.
#[derive(Default)]
pub struct Problems(Mutex<Vec<Problem>>);

impl Problems {
    pub fn note<T>(&self, path: &Path, loaded: &Loaded<T>) {
        if let Loaded::Corrupt { kept, error } = loaded {
            let file = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            let kept = kept.as_ref().map(|p| p.display().to_string()).unwrap_or_default();
            eprintln!("sidefolk: {file} couldn't be read ({error}); kept at {kept}");
            let mut list = self.0.lock().unwrap();
            list.retain(|p| p.file != file);
            list.push(Problem { file, kept, error: error.clone(), backup: backup_of(path).exists() });
        }
    }
    pub fn list(&self) -> Vec<Problem> {
        self.0.lock().unwrap().clone()
    }
}

pub fn backup_of(path: &Path) -> PathBuf {
    path.with_extension("json.bak")
}

fn now_ms() -> u128 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or_default()
}

/// Reads `path`. `migrate` turns an older version's data into the current shape.
pub fn load<T: DeserializeOwned>(path: &Path, migrate: impl FnOnce(u64, Value) -> Value) -> Loaded<T> {
    let bytes = match fs::read(path) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Loaded::Missing,
        Err(e) => return set_aside(path, e.to_string()),
    };
    let parsed = serde_json::from_slice::<Value>(&bytes).map_err(|e| e.to_string()).and_then(|value| {
        let (version, data) = unwrap_envelope(value);
        serde_json::from_value::<T>(migrate(version, data)).map_err(|e| e.to_string())
    });
    match parsed {
        Ok(value) => {
            // The last good copy, for "Restore last good copy" after a later damage.
            let _ = crate::settings::atomic_write(&backup_of(path), &bytes);
            Loaded::Ok(value)
        }
        Err(error) => set_aside(path, error),
    }
}

/// `{ "version": n, "data": … }`, or a file from before envelopes (version 0).
fn unwrap_envelope(value: Value) -> (u64, Value) {
    match value {
        Value::Object(mut map) if map.len() == 2 && map.contains_key("data") && map.get("version").is_some_and(Value::is_u64) => {
            let version = map.get("version").and_then(Value::as_u64).unwrap_or_default();
            (version, map.remove("data").unwrap_or(Value::Null))
        }
        other => (0, other),
    }
}

fn set_aside<T>(path: &Path, error: String) -> Loaded<T> {
    let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let kept = path.with_file_name(format!("{name}.corrupt-{}", now_ms()));
    match fs::rename(path, &kept) {
        Ok(()) => Loaded::Corrupt { kept: Some(kept), error },
        Err(_) => Loaded::Corrupt { kept: None, error },
    }
}

/// Writes `data` as the current `version`, atomically.
pub fn save<T: Serialize>(path: &Path, version: u64, data: &T) -> io::Result<()> {
    let bytes = serde_json::to_vec_pretty(&json!({ "version": version, "data": data }))?;
    crate::settings::atomic_write(path, &bytes)
}

/// Puts the last good copy back. The caller reloads (the app restarts).
pub fn restore(path: &Path) -> io::Result<()> {
    let bytes = fs::read(backup_of(path))?;
    crate::settings::atomic_write(path, &bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    #[derive(Deserialize, Serialize, Default, Debug, PartialEq)]
    struct Thing {
        name: String,
    }

    fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("sidefolk-store-{name}-{}-{}", std::process::id(), now_ms()));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn missing_starts_empty_and_saved_data_reads_back() {
        let dir = temp("roundtrip");
        let path = dir.join("thing.json");
        assert!(matches!(load::<Thing>(&path, |_, v| v), Loaded::Missing));
        save(&path, 1, &Thing { name: "Pip".into() }).unwrap();
        let text = fs::read_to_string(&path).unwrap();
        assert!(text.contains("\"version\": 1") && text.contains("\"data\""));
        let Loaded::Ok(thing) = load::<Thing>(&path, |_, v| v) else { panic!("not ok") };
        assert_eq!(thing.name, "Pip");
        assert!(backup_of(&path).exists());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn reads_files_from_before_envelopes_as_version_zero() {
        let dir = temp("legacy");
        let path = dir.join("thing.json");
        fs::write(&path, r#"{"name":"Old"}"#).unwrap();
        let mut seen = 99;
        let Loaded::Ok(thing) = load::<Thing>(&path, |v, data| {
            seen = v;
            data
        }) else {
            panic!("not ok")
        };
        assert_eq!((seen, thing.name.as_str()), (0, "Old"));
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn damaged_data_is_set_aside_never_overwritten_and_restorable() {
        let dir = temp("corrupt");
        let path = dir.join("thing.json");
        save(&path, 1, &Thing { name: "Good".into() }).unwrap();
        assert!(matches!(load::<Thing>(&path, |_, v| v), Loaded::Ok(_)));
        fs::write(&path, b"{ not json").unwrap();
        let problems = Problems::default();
        let loaded = load::<Thing>(&path, |_, v| v);
        problems.note(&path, &loaded);
        let Loaded::Corrupt { kept: Some(kept), .. } = loaded else { panic!("not corrupt") };
        // The damaged bytes are kept as they were, and the file itself is gone (nothing to overwrite).
        assert_eq!(fs::read(&kept).unwrap(), b"{ not json");
        assert!(!path.exists());
        let problem = &problems.list()[0];
        assert_eq!((problem.file.as_str(), problem.backup), ("thing.json", true));
        // A later save writes a fresh file; the damaged copy stays.
        save(&path, 1, &Thing { name: "New".into() }).unwrap();
        assert_eq!(fs::read(&kept).unwrap(), b"{ not json");
        // The last good copy comes back.
        restore(&path).unwrap();
        let Loaded::Ok(thing) = load::<Thing>(&path, |_, v| v) else { panic!("not ok") };
        assert_eq!(thing.name, "Good");
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn wrong_shapes_count_as_damage() {
        let dir = temp("shape");
        let path = dir.join("thing.json");
        fs::write(&path, r#"[1, 2, 3]"#).unwrap();
        assert!(matches!(load::<Thing>(&path, |_, v| v), Loaded::Corrupt { kept: Some(_), .. }));
        fs::remove_dir_all(dir).unwrap();
    }
}
