//! Characters people made from the template (src/character-import.ts): a folder per character in
//! <data>/characters/<id>/ with one PNG per pose and character.json. The folder is the shareable
//! pack: copy it to a friend's characters folder and it shows up.
use std::{
    collections::BTreeMap,
    fs, io,
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};
use tauri::{Emitter, State};

use crate::bus::Shared;

const POSES: [&str; 16] = ["idle", "blink", "listen", "think", "work1", "work2", "alert", "sad", "note", "write1", "write2", "done", "wave", "sit", "sleep", "dangle"];
const MAX_FRAME: usize = 2 * 1024 * 1024;
const PNG: &[u8] = b"\x89PNG\r\n\x1a\n";

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Character {
    pub id: String,
    pub name: String,
    pub poses: Vec<String>,
}

fn dir(shared: &Shared) -> PathBuf {
    shared.settings.lock().unwrap().dir.join("characters")
}

fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 60 && id.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

fn slug(name: &str) -> String {
    let mut out = String::new();
    for c in name.to_lowercase().chars() {
        if c.is_ascii_alphanumeric() {
            out.push(c);
        } else if !out.ends_with('-') {
            out.push('-');
        }
    }
    let out = out.trim_matches('-').chars().take(40).collect::<String>();
    if out.is_empty() { "character".into() } else { out }
}

fn read(folder: &Path) -> Option<Character> {
    let id = folder.file_name()?.to_str()?.to_string();
    if !valid_id(&id) || !folder.join("idle.png").is_file() {
        return None;
    }
    let name = fs::read(folder.join("character.json"))
        .ok()
        .and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok())
        .and_then(|v| v["name"].as_str().map(String::from))
        .unwrap_or_else(|| id.clone());
    let poses = POSES.iter().filter(|p| folder.join(format!("{p}.png")).is_file()).map(|p| p.to_string()).collect();
    Some(Character { id, name, poses })
}

#[tauri::command]
pub fn list_characters(shared: State<'_, std::sync::Arc<Shared>>) -> Vec<Character> {
    let Ok(entries) = fs::read_dir(dir(&shared)) else { return vec![] };
    let mut list: Vec<Character> = entries.flatten().filter_map(|e| read(&e.path())).collect();
    list.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    list
}

/// Saves a character from the window's import: `frames` maps pose names to base64 PNGs.
#[tauri::command]
pub fn save_character(app: tauri::AppHandle, shared: State<'_, std::sync::Arc<Shared>>, name: String, frames: BTreeMap<String, String>) -> Result<Character, String> {
    let name: String = name.split_whitespace().collect::<Vec<_>>().join(" ").chars().take(24).collect();
    if name.is_empty() {
        return Err("A character needs a name.".into());
    }
    if !frames.contains_key("idle") {
        return Err("A character needs at least the idle pose.".into());
    }
    let mut decoded = Vec::new();
    for (pose, data) in &frames {
        if !POSES.contains(&pose.as_str()) {
            return Err(format!("Unknown pose {pose}."));
        }
        let bytes = decode(data.strip_prefix("data:image/png;base64,").unwrap_or(data)).ok_or("A frame isn't a readable image.")?;
        if bytes.len() > MAX_FRAME || !bytes.starts_with(PNG) {
            return Err(format!("The {pose} frame isn't a PNG image."));
        }
        decoded.push((pose.clone(), bytes));
    }
    let root = dir(&shared);
    let base = slug(&name);
    let id = (1..).map(|n| if n == 1 { base.clone() } else { format!("{base}-{n}") }).find(|id| !root.join(id).exists()).unwrap();
    let folder = root.join(&id);
    fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
    let write = || -> io::Result<()> {
        for (pose, bytes) in &decoded {
            fs::write(folder.join(format!("{pose}.png")), bytes)?;
        }
        fs::write(folder.join("character.json"), serde_json::to_vec_pretty(&serde_json::json!({ "name": name, "made_with": "Sidefolk character template" }))?)
    };
    if let Err(error) = write() {
        let _ = fs::remove_dir_all(&folder);
        return Err(error.to_string());
    }
    let _ = app.emit("characters-changed", ());
    read(&folder).ok_or_else(|| "The character couldn't be read back.".into())
}

/// A character's frames as data URLs, for the companion to draw.
#[tauri::command]
pub fn character_frames(shared: State<'_, std::sync::Arc<Shared>>, id: String) -> Result<BTreeMap<String, String>, String> {
    if !valid_id(&id) {
        return Err("No such character.".into());
    }
    let folder = dir(&shared).join(&id);
    let mut frames = BTreeMap::new();
    for pose in POSES {
        if let Ok(bytes) = fs::read(folder.join(format!("{pose}.png"))) {
            frames.insert(pose.to_string(), format!("data:image/png;base64,{}", encode(&bytes)));
        }
    }
    if !frames.contains_key("idle") {
        return Err("This character is missing its idle pose.".into());
    }
    Ok(frames)
}

#[tauri::command]
pub fn delete_character(app: tauri::AppHandle, shared: State<'_, std::sync::Arc<Shared>>, id: String) -> Result<(), String> {
    if !valid_id(&id) {
        return Err("No such character.".into());
    }
    fs::remove_dir_all(dir(&shared).join(&id)).map_err(|e| e.to_string())?;
    let _ = app.emit("characters-changed", ());
    Ok(())
}

/// Puts the template, or a character exported as one sheet (`name`), in ~/Downloads and shows it
/// in Finder.
#[tauri::command]
pub fn save_template(png: String, name: Option<String>) -> Result<String, String> {
    let bytes = decode(png.strip_prefix("data:image/png;base64,").unwrap_or(&png)).filter(|b| b.starts_with(PNG)).ok_or("The picture couldn't be read.")?;
    let file = match name {
        Some(name) => format!("{}.sidefolk.png", slug(&name)),
        None => "sidefolk-character-template.png".into(),
    };
    let downloads = std::env::var_os("HOME").map(PathBuf::from).ok_or("No home folder.")?.join("Downloads");
    let path = downloads.join(&file);
    fs::write(&path, bytes).map_err(|e| e.to_string())?;
    let _ = std::process::Command::new("open").arg("-R").arg(&path).spawn();
    Ok(format!("Saved to Downloads as {file}."))
}

const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn encode(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let n = (u32::from(chunk[0]) << 16) | (u32::from(*chunk.get(1).unwrap_or(&0)) << 8) | u32::from(*chunk.get(2).unwrap_or(&0));
        for i in 0..4 {
            if i <= chunk.len() {
                out.push(ALPHABET[(n >> (18 - 6 * i) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
    out
}

fn decode(text: &str) -> Option<Vec<u8>> {
    let text = text.trim_end_matches('=');
    let mut out = Vec::with_capacity(text.len() * 3 / 4);
    let (mut acc, mut bits) = (0u32, 0);
    for c in text.bytes() {
        acc = (acc << 6) | ALPHABET.iter().position(|&a| a == c)? as u32;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
            acc &= (1 << bits) - 1;
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_round_trips() {
        for sample in [&b""[..], b"f", b"fo", b"foo", b"foob", b"\x89PNG\r\n\x1a\n\x00\xff"] {
            assert_eq!(decode(&encode(sample)).unwrap(), sample);
        }
        assert_eq!(encode(b"foobar"), "Zm9vYmFy");
        assert_eq!(encode(b"fo"), "Zm8=");
        assert!(decode("not*base64").is_none());
    }

    #[test]
    fn ids_and_folders() {
        assert_eq!(slug("Bun the Brave!"), "bun-the-brave");
        assert!(valid_id("bun-2") && !valid_id("../x") && !valid_id(""));
        let folder = std::env::temp_dir().join(format!("sidefolk-char-{}", std::process::id())).join("bun");
        fs::create_dir_all(&folder).unwrap();
        assert!(read(&folder).is_none());
        fs::write(folder.join("idle.png"), PNG).unwrap();
        fs::write(folder.join("wave.png"), PNG).unwrap();
        let c = read(&folder).unwrap();
        assert_eq!((c.name.as_str(), c.poses.clone()), ("bun", vec!["idle".to_string(), "wave".to_string()]));
        fs::remove_dir_all(folder.parent().unwrap()).unwrap();
    }
}
