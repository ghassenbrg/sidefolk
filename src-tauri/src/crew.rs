//! The crew (crew.json in the data directory) is decided by the page: which pets exist and
//! what each looks after. Rust stores it and lists the pets in the tray menu.
use serde_json::Value;
use std::{fs, io, path::Path};

/// Far more than any real crew; keeps a runaway page from filling the disk.
const MAX_BYTES: usize = 256 * 1024;

pub fn load(dir: &Path) -> Value {
    fs::read(dir.join("crew.json"))
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or(Value::Null)
}

pub fn save(dir: &Path, crew: &Value) -> io::Result<()> {
    if !crew.is_object() {
        return Err(io::Error::other("The crew must be an object"));
    }
    let bytes = serde_json::to_vec_pretty(crew)?;
    if bytes.len() > MAX_BYTES {
        return Err(io::Error::other("The crew file is too large"));
    }
    crate::settings::atomic_write(&dir.join("crew.json"), &bytes)
}

/// (id, "Pip · api") for each crew pet, for the tray.
pub fn menu_entries(crew: &Value) -> Vec<(String, String)> {
    let Some(pets) = crew["pets"].as_array() else {
        return Vec::new();
    };
    pets.iter()
        .filter_map(|pet| {
            let id = pet["id"].as_str()?;
            let name = pet["name"].as_str()?;
            let project = pet["bindings"].as_array().and_then(|bindings| {
                bindings
                    .iter()
                    .find(|b| b["kind"] == "project")
                    .and_then(|b| b["key"].as_str())
                    .and_then(|key| key.rsplit('/').find(|part| !part.is_empty()))
            });
            Some((
                id.to_string(),
                match project {
                    Some(project) => format!("{name} · {project}"),
                    None => name.to_string(),
                },
            ))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn lists_pets_with_their_projects() {
        let crew = json!({ "pets": [
            { "id": "a", "name": "Pip", "bindings": [{ "kind": "project", "key": "/Users/me/git/api" }] },
            { "id": "b", "name": "Mochi", "bindings": [{ "kind": "agent", "key": "codex" }] },
            { "name": "broken" }
        ]});
        assert_eq!(
            menu_entries(&crew),
            vec![("a".into(), "Pip · api".into()), ("b".into(), "Mochi".into())]
        );
        assert!(menu_entries(&Value::Null).is_empty());
    }
    #[test]
    fn refuses_non_objects() {
        let dir = std::env::temp_dir().join(format!("sidefolk-crew-{}", std::process::id()));
        assert!(save(&dir, &json!([1])).is_err());
        save(&dir, &json!({ "pets": [] })).unwrap();
        assert_eq!(load(&dir), json!({ "pets": [] }));
        fs::remove_dir_all(dir).unwrap();
    }
}
