//! Custom pets: imported glb models (kept in <data dir>/models) and "describe your pet" from a
//! photo, which asks Claude Code (one small Haiku call) only when the user picks a photo.
use std::{
    fs, io,
    path::{Path, PathBuf},
    process::Stdio,
    time::Duration,
};

use tauri::{AppHandle, ipc::Response};
use tauri_plugin_dialog::DialogExt;

const MAX_MODEL_BYTES: u64 = 20 * 1024 * 1024;
const PHOTO_WAIT: Duration = Duration::from_secs(90);

fn models_dir(data_dir: &Path) -> PathBuf {
    data_dir.join("models")
}

/// Only plain names, so a page cannot read outside the models folder.
fn valid_name(name: &str) -> bool {
    name.ends_with(".glb")
        && name.len() <= 80
        && !name.starts_with('.')
        && name.chars().all(|c| c.is_ascii_alphanumeric() || "-_.".contains(c))
}

/// Copies a glb into the models folder under a safe name and returns that name.
pub fn import(data_dir: &Path, source: &Path) -> io::Result<String> {
    let meta = fs::metadata(source)?;
    if meta.len() > MAX_MODEL_BYTES {
        return Err(io::Error::other("That model is larger than 20 MB."));
    }
    let bytes = fs::read(source)?;
    if bytes.get(..4) != Some(b"glTF") {
        return Err(io::Error::other("That file is not a binary glTF (.glb) model."));
    }
    let stem: String = source
        .file_stem()
        .map(|s| s.to_string_lossy().chars().map(|c| if c.is_ascii_alphanumeric() || c == '-' { c } else { '_' }).take(60).collect())
        .unwrap_or_default();
    let name = format!("{}.glb", if stem.is_empty() { "model".into() } else { stem });
    crate::settings::atomic_write(&models_dir(data_dir).join(&name), &bytes)?;
    Ok(name)
}

pub fn list(data_dir: &Path) -> Vec<String> {
    let mut names: Vec<String> = fs::read_dir(models_dir(data_dir))
        .map(|dir| dir.flatten().map(|f| f.file_name().to_string_lossy().into_owned()).filter(|n| valid_name(n)).collect())
        .unwrap_or_default();
    names.sort();
    names
}

pub fn read(data_dir: &Path, name: &str) -> io::Result<Response> {
    if !valid_name(name) {
        return Err(io::Error::other("Not a model name"));
    }
    Ok(Response::new(fs::read(models_dir(data_dir).join(name))?))
}

/// Asks the user for a file (an image or a glb). Runs off the main thread.
pub fn pick(app: &AppHandle, kind: &str) -> Option<PathBuf> {
    let dialog = app.dialog().file();
    let dialog = match kind {
        "photo" => dialog.add_filter("Photo", &["png", "jpg", "jpeg", "webp", "heic"]),
        _ => dialog.add_filter("glTF model", &["glb"]),
    };
    dialog.blocking_pick_file()?.into_path().ok()
}

const PHOTO_PROMPT: &str = "Look at the image file named in this message (use the Read tool). It shows someone's pet or a character. Pick the closest settings for a small chibi desktop pet. species: bunny, cat or fox. palette (the coat color): snow (white or cream), cocoa (brown), midnight (black or grey), peach (pink), sage (green), honey (yellow), ember (orange or red). accessory: none, glasses, headphones, flower or beanie. Reply with only JSON, for example {\"species\":\"cat\",\"palette\":\"midnight\",\"accessory\":\"none\"}. Image file: ";

/// One small Claude Code call that turns a photo into kit settings (JSON text).
pub async fn describe_photo(path: &Path) -> Result<String, String> {
    let dir = path.parent().ok_or("That photo has no folder")?;
    let name = path.file_name().ok_or("That photo has no name")?.to_string_lossy().into_owned();
    let child = tokio::process::Command::new("claude")
        .arg("-p")
        .arg(format!("{PHOTO_PROMPT}{name}"))
        .args(["--model", "haiku", "--output-format", "text", "--allowedTools=Read"])
        .current_dir(dir)
        .env("PATH", crate::codex::agent_path())
        .env_remove("CLAUDECODE")
        .env_remove("CLAUDE_CODE_ENTRYPOINT")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .map_err(|e| format!("Describing a photo needs Claude Code installed ({e})."))?;
    let output = tokio::time::timeout(PHOTO_WAIT, child.wait_with_output())
        .await
        .map_err(|_| "Claude took too long to look at the photo.".to_string())?
        .map_err(|e| e.to_string())?;
    let text = String::from_utf8_lossy(&output.stdout);
    let json = text
        .find('{')
        .and_then(|start| text[start..].find('}').map(|end| &text[start..=start + end]))
        .ok_or_else(|| format!("Claude did not answer with settings: {}", crate::bus::clip(&text, 120)))?;
    Ok(json.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn names_stay_inside_the_folder() {
        assert!(valid_name("my-cat_2.glb"));
        assert!(!valid_name("../x.glb"));
        assert!(!valid_name(".hidden.glb"));
        assert!(!valid_name("a/b.glb"));
        assert!(!valid_name("x.gltf"));
    }
    /// One small live Claude call: `cargo test describes_a_photo -- --ignored`.
    #[tokio::test]
    #[ignore = "calls Claude Code (Haiku) once"]
    async fn describes_a_photo() {
        let photo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../art/concepts/hero-turnaround.png");
        let json: serde_json::Value = serde_json::from_str(&describe_photo(&photo).await.unwrap()).unwrap();
        assert_eq!(json["species"], "bunny", "{json}");
    }

    #[test]
    fn imports_only_glb() {
        let dir = std::env::temp_dir().join(format!("sidefolk-models-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let fake = dir.join("not a model.glb");
        fs::write(&fake, b"hello").unwrap();
        assert!(import(&dir, &fake).is_err());
        let real = dir.join("My Cat!.glb");
        fs::write(&real, b"glTF\x02\x00\x00\x00").unwrap();
        assert_eq!(import(&dir, &real).unwrap(), "My_Cat_.glb");
        assert_eq!(list(&dir), vec!["My_Cat_.glb".to_string()]);
        fs::remove_dir_all(dir).unwrap();
    }
}
