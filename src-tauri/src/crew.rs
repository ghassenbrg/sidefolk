//! crew.json in the data directory: the companion's name, decided by the page. (v0.1 kept a whole
//! crew there; the file name stays so existing installs keep their companion's name.)
use serde_json::Value;
use std::{io, path::Path};

/// Far more than the file needs; keeps a runaway page from filling the disk.
const MAX_BYTES: usize = 256 * 1024;

pub fn load(dir: &Path, problems: &crate::store::Problems) -> Value {
    let path = dir.join("crew.json");
    // An object, with `main` an object when it's there; anything else is damage.
    let loaded = crate::store::load::<Value>(&path, 1, |v| v.is_object() && v.get("main").is_none_or(Value::is_object), |_, data| data);
    problems.note(&path, &loaded);
    match loaded {
        crate::store::Loaded::Ok(value) => value,
        _ => Value::Null,
    }
}

/// Refuses while a damaged crew.json couldn't be set aside (`problems`), so it's never overwritten.
pub fn save(dir: &Path, crew: &Value, problems: &crate::store::Problems) -> io::Result<()> {
    if problems.blocks(&dir.join("crew.json")) {
        return Err(io::Error::other("Your companion's file couldn't be read, so I won't write over it."));
    }
    if !crew.is_object() {
        return Err(io::Error::other("crew.json must be an object"));
    }
    if serde_json::to_vec(crew)?.len() > MAX_BYTES {
        return Err(io::Error::other("crew.json is too large"));
    }
    crate::store::save(&dir.join("crew.json"), 1, crew)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use serde_json::json;
    #[test]
    fn refuses_non_objects() {
        let dir = std::env::temp_dir().join(format!("sidefolk-crew-{}", std::process::id()));
        assert!(save(&dir, &json!([1]), &Default::default()).is_err());
        save(&dir, &json!({ "main": { "name": "Pip" } }), &Default::default()).unwrap();
        assert_eq!(load(&dir, &Default::default()), json!({ "main": { "name": "Pip" } }));
        // A crew.json that is valid JSON but not a crew is damage, not an empty companion.
        fs::write(dir.join("crew.json"), "[]").unwrap();
        let problems = crate::store::Problems::default();
        assert_eq!(load(&dir, &problems), Value::Null);
        assert_eq!(problems.list()[0].file, "crew.json");
        fs::remove_dir_all(dir).unwrap();
    }
}
