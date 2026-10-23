//! "Speak out loud": pets read their lines with macOS voices (`say`). One line at a time; a
//! new line stops the one still being spoken. Off by default.
use std::{process::Command, sync::Mutex};

use serde::Serialize;

static SPEAKING: Mutex<Option<std::process::Child>> = Mutex::new(None);

/// Reads `text` aloud. `pitch` (0.5..2) shifts the voice so pets don't all sound the same.
#[tauri::command]
pub fn speak(text: String, voice: Option<String>, pitch: Option<f64>) -> Result<(), String> {
    let text = crate::bus::clip(&text, 280);
    let mut current = SPEAKING.lock().unwrap();
    if let Some(mut child) = current.take() {
        let _ = child.kill();
        let _ = child.wait();
    }
    if text.is_empty() {
        return Ok(());
    }
    // `say` reads embedded commands like [[pbas 50]]; set the pitch base, then the words.
    let base = (pitch.unwrap_or(1.0).clamp(0.5, 2.0) * 50.0).round();
    let words = text.replace("[[", "[ [");
    let mut command = Command::new("say");
    if let Some(voice) = voice.filter(|v| !v.is_empty() && v.chars().all(|c| c.is_alphanumeric() || " ()-'".contains(c))) {
        command.args(["-v", &voice]);
    }
    let child = command
        .args(["-r", "190", "--", &format!("[[pbas {base}]] {words}")])
        .spawn()
        .map_err(|e| format!("Could not speak: {e}"))?;
    *current = Some(child);
    Ok(())
}

#[derive(Serialize, PartialEq, Debug)]
pub struct VoiceInfo {
    name: String,
    language: String,
}

fn parse(listing: &str) -> Vec<VoiceInfo> {
    listing
        .lines()
        .filter_map(|line| {
            // "Samantha            en_US    # Hello! My name is Samantha."
            let head = line.split('#').next()?.trim_end();
            let (name, language) = head.rsplit_once(char::is_whitespace)?;
            Some(VoiceInfo { name: name.trim().to_string(), language: language.to_string() })
        })
        .filter(|v| !v.name.is_empty() && v.language.contains('_'))
        .collect()
}

/// The voices installed on this Mac (System Settings → Accessibility → Spoken Content adds more).
#[tauri::command]
pub fn voices() -> Vec<VoiceInfo> {
    Command::new("say")
        .args(["-v", "?"])
        .output()
        .map(|out| parse(&String::from_utf8_lossy(&out.stdout)))
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn parses_the_voice_list() {
        let listing = "Albert              en_US    # Hello! My name is Albert.\nGood News           en_US    # Hello!\nAmélie              fr_CA    # Bonjour!\n";
        let voices = parse(listing);
        assert_eq!(voices.len(), 3);
        assert_eq!(voices[1], VoiceInfo { name: "Good News".into(), language: "en_US".into() });
    }
}
