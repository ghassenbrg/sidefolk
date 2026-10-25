//! V1-X6: native-only updater and fail-closed minimum-safe-version policy.
//! The lead must wire this module into main and the request lifecycle (docs/RELEASE.md).
use semver::Version;
use serde_json::Value;
use std::sync::Mutex;
use std::time::Duration;
use tauri_plugin_updater::{Update, UpdaterExt};

#[derive(Default)]
pub struct Safety {
    minimum: Mutex<Option<Version>>,
    checked: Mutex<bool>,
}

impl Safety {
    /// Keep the greatest minimum seen: an older feed cannot silently undo a kill switch.
    /// Seed this with the persisted minimum at startup, but a fresh check is still required.
    pub fn restore(&self, minimum: Version) {
        let mut saved = self.minimum.lock().unwrap();
        if saved.as_ref().is_none_or(|old| minimum > *old) {
            *saved = Some(minimum);
        }
    }

    pub fn observe(&self, minimum: Version) {
        self.restore(minimum);
        *self.checked.lock().unwrap() = true;
    }

    pub fn minimum_safe_version(&self) -> Option<String> {
        self.minimum.lock().unwrap().as_ref().map(ToString::to_string)
    }

    pub fn invalidate(&self) {
        *self.checked.lock().unwrap() = false;
    }

    pub fn may_hold(&self, current: &str) -> bool {
        if !*self.checked.lock().unwrap() {
            return false;
        }
        let Ok(current) = Version::parse(current) else { return false };
        self.minimum.lock().unwrap().as_ref().is_some_and(|minimum| current >= *minimum)
    }
}

/// Validate metadata even when the offered version equals the running version.
/// The archive signature is verified by the official plugin at download/install time;
/// metadata itself is transported over HTTPS, not authenticated by that archive signature.
pub fn feed_minimum(feed: &Value) -> Result<Version, String> {
    let parse = |key| feed[key].as_str().and_then(|s| Version::parse(s).ok())
        .ok_or_else(|| format!("Missing or invalid {key}"));
    let version = parse("version")?;
    let minimum = parse("min_safe_version")?;
    if minimum > version || !minimum.pre.is_empty() || !version.pre.is_empty() {
        return Err("Feed needs stable versions with min_safe_version <= version".into());
    }
    let platform = &feed["platforms"]["darwin-aarch64"];
    let url = platform["url"].as_str().and_then(|s| tauri::Url::parse(s).ok());
    if !url.is_some_and(|u| u.scheme() == "https" && u.host_str() == Some("github.com")
        && u.username().is_empty() && u.password().is_none()
        && u.path().contains("/releases/download/"))
        || platform["signature"].as_str().is_none_or(|s| s.trim().is_empty())
        || feed["notes"].as_str().is_none_or(|s| s.trim().is_empty())
    {
        return Err("Feed needs GitHub HTTPS release artifact, signature and release notes".into());
    }
    Ok(minimum)
}

/// Check on launch, daily and manually. No install here; the caller retains the Update
/// in Rust and installs only after showing notes and receiving explicit user consent.
pub async fn check(app: &tauri::AppHandle, safety: &Safety) -> Result<Option<Update>, String> {
    let result = async {
        let update = app.updater_builder()
            // Fetch raw_json even for the same version so policy is never skipped.
            .version_comparator(|_, _| true)
            .timeout(Duration::from_secs(15))
            .build().map_err(|e| e.to_string())?
            .check().await.map_err(|e| e.to_string())?
            .ok_or("No safety policy in update response")?;
        let minimum = feed_minimum(&update.raw_json)?;
        let offered = Version::parse(&update.version).map_err(|e| e.to_string())?;
        let current = Version::parse(&update.current_version).map_err(|e| e.to_string())?;
        safety.observe(minimum);
        Ok((offered > current).then_some(update))
    }.await;
    if result.is_err() { safety.invalidate(); }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    fn feed() -> Value {
        serde_json::json!({"version":"0.9.1", "min_safe_version":"0.9.0",
            "notes":"Pip has a safer update.", "platforms":{"darwin-aarch64":{
                "url":"https://github.com/owner/sidefolk/releases/download/v0.9.1/Sidefolk.app.tar.gz",
                "signature":"test-only-signature"}}})
    }
    #[test]
    fn blocks_unknown_old_and_invalid_versions() {
        let safety = Safety::default();
        assert!(!safety.may_hold("0.9.1"));
        safety.restore(feed_minimum(&feed()).unwrap());
        assert!(!safety.may_hold("0.9.1"));
        assert_eq!(safety.minimum_safe_version().as_deref(), Some("0.9.0"));
        safety.observe(feed_minimum(&feed()).unwrap());
        assert!(!safety.may_hold("0.8.9"));
        assert!(!safety.may_hold("invalid"));
        assert!(safety.may_hold("0.9.0"));
        assert!(safety.may_hold("0.10.0"));
        safety.invalidate();
        assert!(!safety.may_hold("0.9.1"));
    }
    #[test]
    fn minimum_never_moves_backwards() {
        let safety = Safety::default();
        safety.observe(Version::parse("0.9.1").unwrap());
        safety.observe(Version::parse("0.9.0").unwrap());
        assert!(!safety.may_hold("0.9.0"));
    }
    #[test]
    fn rejects_incomplete_unsafe_and_inconsistent_feeds() {
        assert!(feed_minimum(&feed()).is_ok());
        for (key, value) in [("min_safe_version", Value::Null),
            ("min_safe_version", "0.9.2".into()), ("version", "bad".into()),
            ("version", "0.9.1-beta.1".into()), ("notes", "".into())] {
            let mut f = feed(); f[key] = value;
            assert!(feed_minimum(&f).is_err());
        }
        for url in ["http://github.com/o/r/releases/download/v1/a", "https://evil.test/a",
            "https://user@github.com/o/r/releases/download/v1/a"] {
            let mut f = feed(); f["platforms"]["darwin-aarch64"]["url"] = url.into();
            assert!(feed_minimum(&f).is_err());
        }
        let mut f = feed(); f["platforms"]["darwin-aarch64"]["signature"] = "".into();
        assert!(feed_minimum(&f).is_err());
    }
}
