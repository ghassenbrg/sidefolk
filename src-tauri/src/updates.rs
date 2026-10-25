//! Native update offers and the atomic gate around creating/answering held requests.
use crate::{bus::Shared, release::Safety, store};
use serde::{Deserialize, Serialize};
use std::{path::{Path, PathBuf}, sync::{Arc, Mutex, atomic::{AtomicBool, Ordering}}};
use tauri::{AppHandle, Emitter, Manager, WebviewWindow};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons};
use tauri_plugin_updater::Update;

#[derive(Default, Serialize, Deserialize)]
struct Policy { minimum: Option<semver::Version> }
struct Offer { id: String, update: Update }
#[derive(Default)]
struct Progress { checking: bool, installing: bool, offer: Option<Offer>, error: Option<String>, installed: bool }
pub struct Updates {
    gate: Mutex<()>,
    safety: Safety,
    policy: Mutex<Policy>,
    progress: Mutex<Progress>,
    path: PathBuf,
    blocked: bool,
    configured: bool,
    paused: AtomicBool,
}
#[derive(Clone, Serialize)]
pub struct Status {
    configured: bool, checking: bool, installing: bool, installed: bool,
    version: Option<String>, notes: Option<String>, offer_id: Option<String>,
    error: Option<String>, paused: bool, holding_allowed: bool,
}
impl Updates {
    fn load(dir: &Path, problems: &store::Problems, configured: bool, paused: bool) -> Self {
        let path = dir.join("update-policy.json");
        let mut loaded = store::load::<Policy>(&path, 1, |data| data.as_object().is_some_and(|map| map.len() == 1 && map.get("minimum").is_some_and(serde_json::Value::is_string)), |_, data| data);
        // Quarantine removes the active file. Missing is a first install only when no prior
        // policy survives; otherwise every later restart must keep blocking until recovery.
        if matches!(loaded, store::Loaded::Missing) {
            let evidence = match std::fs::read_dir(dir) {
                Ok(entries) => entries.filter_map(Result::ok).map(|entry| entry.path()).find(|entry| {
                    entry.file_name().is_some_and(|name| name.to_string_lossy().starts_with("update-policy.json.corrupt-"))
                }).or_else(|| store::backup_of(&path).exists().then(|| store::backup_of(&path))),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
                Err(_) => Some(dir.to_path_buf()),
            };
            if let Some(kept) = evidence {
                loaded = store::Loaded::Corrupt { kept: Some(kept), error: "A previous update policy needs explicit recovery.".into() };
            }
        }
        problems.note(&path, &loaded);
        let blocked = matches!(loaded, store::Loaded::Corrupt { .. });
        let policy = loaded.or_default();
        let safety = Safety::default();
        if let Some(minimum) = &policy.minimum { safety.restore(minimum.clone()); }
        Self { gate: Mutex::new(()), safety, policy: Mutex::new(policy), progress: Mutex::default(), path, blocked, configured, paused: AtomicBool::new(paused) }
    }
    fn act<T>(&self, action: impl FnOnce() -> T) -> Option<T> {
        let _gate = self.gate.lock().unwrap();
        self.allowed().then(action)
    }
    fn allowed(&self) -> bool {
        !self.blocked && !self.paused.load(Ordering::Relaxed)
            && ((cfg!(debug_assertions) && !self.configured) || self.safety.may_hold(env!("CARGO_PKG_VERSION")))
    }
    fn status(&self) -> Status {
        let p = self.progress.lock().unwrap();
        Status { configured: self.configured, checking: p.checking, installing: p.installing, installed: p.installed,
            version: p.offer.as_ref().map(|o| o.update.version.clone()), notes: p.offer.as_ref().and_then(|o| o.update.body.clone()),
            offer_id: p.offer.as_ref().map(|o| o.id.clone()), error: p.error.clone(), paused: self.paused.load(Ordering::Relaxed), holding_allowed: self.allowed() }
    }
    fn persist(&self, minimum: semver::Version) -> Result<semver::Version, String> {
        if self.blocked { return Err("Update policy could not be read; restore its last good copy.".into()); }
        let mut policy = self.policy.lock().unwrap();
        let minimum = policy.minimum.as_ref().map_or(minimum.clone(), |old| old.max(&minimum).clone());
        store::save(&self.path, 1, &Policy { minimum: Some(minimum.clone()) }).map_err(|e| e.to_string())?;
        policy.minimum = Some(minimum.clone());
        Ok(minimum)
    }
}

/// Gate publication and request mutations share this mutex, closing policy-change races.
pub fn guarded<T>(app: &AppHandle, action: impl FnOnce() -> T) -> Option<T> {
    let state = app.try_state::<Updates>()?;
    state.act(action)
}
pub fn may_hold(app: &AppHandle) -> bool { guarded(app, || true).unwrap_or(false) }
pub fn paused(app: &AppHandle) -> bool { app.try_state::<Updates>().is_some_and(|s| s.paused.load(Ordering::Relaxed)) }
fn release_requests(requests: &crate::requests::Requests) -> Vec<String> {
    requests.list().into_iter().filter_map(|r| requests.release(&r.id).then_some(r.id)).collect()
}
fn release_pending(app: &AppHandle) {
    let shared = app.state::<Arc<Shared>>();
    for id in release_requests(&shared.requests) { let _ = app.emit("permission-released", id); }
    shared.requests.changed(app);
}
fn publish(app: &AppHandle) { let _ = app.emit("update-status", app.state::<Updates>().status()); }
pub fn toggle_pause(app: &AppHandle) -> tauri::Result<()> {
    let state = app.state::<Updates>();
    { let _gate = state.gate.lock().unwrap();
      let paused = !state.paused.load(Ordering::Relaxed);
      app.state::<Arc<Shared>>().settings.lock().unwrap().update(|settings| settings.answers_paused = paused)?;
      state.paused.store(paused, Ordering::Relaxed);
      if paused { release_pending(app); }
    }
    publish(app);
    let _ = crate::tray::refresh(app);
    Ok(())
}

pub fn setup(app: &AppHandle, dir: &Path, problems: &store::Problems) {
    let config = serde_json::to_value(&app.config().plugins).unwrap_or_default();
    let configured = config["updater"]["pubkey"].as_str().is_some_and(|s| !s.is_empty())
        && config["updater"]["endpoints"].as_array().is_some_and(|a| !a.is_empty());
    let paused = app.state::<Arc<Shared>>().settings.lock().unwrap().value.answers_paused;
    app.manage(Updates::load(dir, problems, configured, paused));
    if configured {
        let handle = app.clone();
        tauri::async_runtime::spawn(async move { loop {
            let _ = check(&handle).await;
            tokio::time::sleep(std::time::Duration::from_secs(86_400)).await;
        } });
    }
}
async fn check(app: &AppHandle) -> Result<Status, String> {
    let state = app.state::<Updates>();
    if !state.configured { return Err("Updates aren't configured for this build.".into()); }
    { let mut p = state.progress.lock().unwrap();
      if p.checking || p.installing { return Err("An update operation is already in progress.".into()); }
      p.checking = true;
    }
    publish(app);
    let probe = Safety::default();
    let result = crate::release::check(app, &probe).await.and_then(|offer| {
        let minimum = probe.minimum_safe_version().ok_or("Missing update safety policy")?.parse::<semver::Version>().map_err(|e| e.to_string())?;
        state.persist(minimum).map(|minimum| (offer, minimum))
    });
    { let _gate = state.gate.lock().unwrap();
      let mut p = state.progress.lock().unwrap();
      p.checking = false;
      match result {
          Ok((offer, minimum)) => {
              state.safety.observe(minimum); p.error = None;
              p.offer = offer.map(|update| Offer { id: format!("{}-{}", update.version, crate::journal::now_ms()), update });
          }
          Err(error) => { state.safety.invalidate(); p.offer = None; p.error = Some(error); }
      }
      if !state.allowed() { release_pending(app); }
    }
    publish(app);
    Ok(state.status())
}
#[tauri::command]
pub fn update_status(app: AppHandle) -> Status { app.state::<Updates>().status() }
#[tauri::command]
pub async fn check_updates(app: AppHandle) -> Result<Status, String> { check(&app).await }
async fn confirm(app: &AppHandle, title: &str, message: String, yes: &str) -> bool {
    let (tx, rx) = tokio::sync::oneshot::channel();
    app.dialog().message(message).title(title).buttons(MessageDialogButtons::OkCancelCustom(yes.into(), "Cancel".into())).show(move |yes| { let _ = tx.send(yes); });
    rx.await.unwrap_or(false)
}
#[tauri::command]
pub async fn install_update(app: AppHandle, window: WebviewWindow, offer_id: String) -> Result<(), String> {
    if window.label() != "preferences" { return Err("Install updates from Sidefolk Settings.".into()); }
    let state = app.state::<Updates>();
    let description = { let p = state.progress.lock().unwrap();
      let offer = p.offer.as_ref().filter(|o| o.id == offer_id).ok_or("Check for updates again; this offer has ended.")?;
      format!("Sidefolk {}\n\n{}\n\nDownload and install this signed update?", offer.update.version, offer.update.body.as_deref().unwrap_or(""))
    };
    if !confirm(&app, "Install Sidefolk update?", description, "Install").await { return Ok(()); }
    let offer = { let mut p = state.progress.lock().unwrap();
      if p.checking || p.installing || !p.offer.as_ref().is_some_and(|o| o.id == offer_id) { return Err("The update changed; check again.".into()); }
      p.installing = true; p.offer.take().unwrap()
    };
    publish(&app);
    let result = offer.update.download_and_install(|_, _| {}, || {}).await.map_err(|e| e.to_string());
    { let mut p = state.progress.lock().unwrap(); p.installing = false; p.installed = result.is_ok(); p.error = result.as_ref().err().cloned(); }
    publish(&app);
    result?;
    if confirm(&app, "Restart Sidefolk?", "The update is installed. Restart Sidefolk to finish?".into(), "Restart").await { app.restart(); }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn policy_or_pause_releases_holds_and_blocks_late_answers_and_creation() {
        let dir = std::env::temp_dir().join(format!("sidefolk-gate-{}", crate::journal::now_ms()));
        let state = Updates::load(&dir, &store::Problems::default(), true, false);
        let requests = crate::requests::Requests::default();
        state.safety.observe(env!("CARGO_PKG_VERSION").parse().unwrap());
        let (ask, _answer) = state.act(|| requests.open("claude", "s", "/tmp", "", "Bash", serde_json::json!({"command":"true"}), true, crate::journal::now_ms() + 60_000)).flatten().unwrap();
        { let _gate = state.gate.lock().unwrap();
          state.safety.invalidate();
          assert_eq!(release_requests(&requests), vec![ask.id.clone()]);
        }
        assert!(state.act(|| requests.answer(&ask.id, crate::bus::Decision::Allow)).is_none());
        assert!(requests.answer(&ask.id, crate::bus::Decision::Allow).is_err());
        assert!(state.act(|| requests.open("claude", "s", "", "", "Bash", serde_json::json!({"command":"true"}), true, 0)).is_none());
        state.safety.observe(env!("CARGO_PKG_VERSION").parse().unwrap());
        state.paused.store(true, Ordering::Relaxed);
        assert!(state.act(|| true).is_none());
        state.safety.observe("999.0.0".parse().unwrap());
        state.paused.store(false, Ordering::Relaxed);
        assert!(state.act(|| true).is_none(), "Resume cannot bypass minimum safe version");
    }
    #[test]
    fn policy_persists_the_greatest_minimum_and_preserves_corrupt_files() {
        let dir = std::env::temp_dir().join(format!("sidefolk-policy-{}", crate::journal::now_ms()));
        let state = Updates::load(&dir, &store::Problems::default(), true, false);
        assert_eq!(state.persist("0.9.2".parse().unwrap()).unwrap().to_string(), "0.9.2");
        assert_eq!(state.persist("0.9.1".parse().unwrap()).unwrap().to_string(), "0.9.2");
        let restored = Updates::load(&dir, &store::Problems::default(), true, false);
        assert!(!restored.allowed(), "a persisted policy needs a fresh check");
        assert_eq!(restored.policy.lock().unwrap().minimum.as_ref().unwrap().to_string(), "0.9.2");
        std::fs::write(&state.path, b"{broken").unwrap();
        let damaged = Updates::load(&dir, &store::Problems::default(), true, false);
        assert!(damaged.blocked);
        assert!(damaged.persist("0.9.3".parse().unwrap()).is_err());
        assert!(!damaged.path.exists());
        assert!(std::fs::read_dir(&dir).unwrap().any(|e| e.unwrap().file_name().to_string_lossy().contains("corrupt")));
        for _ in 0..2 {
            let restarted = Updates::load(&dir, &store::Problems::default(), true, false);
            assert!(restarted.blocked);
            assert!(restarted.persist("0.0.1".parse().unwrap()).is_err());
            restarted.safety.observe("0.0.1".parse().unwrap());
            assert!(!restarted.allowed(), "a stale feed cannot lift the quarantine across restarts");
        }
        store::restore(&state.path).unwrap();
        let recovered = Updates::load(&dir, &store::Problems::default(), true, false);
        assert!(!recovered.blocked);
        assert_eq!(recovered.policy.lock().unwrap().minimum.as_ref().unwrap().to_string(), "0.9.2");
        std::fs::remove_dir_all(dir).unwrap();
    }
}
