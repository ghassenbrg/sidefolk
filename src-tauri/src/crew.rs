//! crew.json in the data directory: the companion's name, decided by the page. (v0.1 kept a whole
//! crew there; the file name stays so existing installs keep their companion's name.)
use serde_json::Value;
use std::{fs, io, path::Path};

/// Far more than the file needs; keeps a runaway page from filling the disk.
const MAX_BYTES: usize = 256 * 1024;

pub fn load(dir: &Path) -> Value {
    fs::read(dir.join("crew.json"))
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or(Value::Null)
}

pub fn save(dir: &Path, crew: &Value) -> io::Result<()> {
    if !crew.is_object() {
        return Err(io::Error::other("crew.json must be an object"));
    }
    let bytes = serde_json::to_vec_pretty(crew)?;
    if bytes.len() > MAX_BYTES {
        return Err(io::Error::other("crew.json is too large"));
    }
    crate::settings::atomic_write(&dir.join("crew.json"), &bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn refuses_non_objects() {
        let dir = std::env::temp_dir().join(format!("sidefolk-crew-{}", std::process::id()));
        assert!(save(&dir, &json!([1])).is_err());
        save(&dir, &json!({ "main": { "name": "Pip" } })).unwrap();
        assert_eq!(load(&dir), json!({ "main": { "name": "Pip" } }));
        fs::remove_dir_all(dir).unwrap();
    }
}
