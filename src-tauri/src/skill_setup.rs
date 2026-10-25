//! Optional skill installation, reached only by an explicit app button and native confirmation.
//! No agent CLI, MCP connection or global settings/config file is touched.
use std::{
    fs, io::{self, Read, Write}, path::{Component, Path, PathBuf},
    sync::{Arc, atomic::{AtomicBool, AtomicU64, Ordering}},
};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, WebviewWindow};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons};

const SKILL: &str = include_str!("../../skills/sidefolk/SKILL.md");
const METADATA: &str = include_str!("../../skills/sidefolk/agents/openai.yaml");
const MANAGED: [&str; 2] = ["SKILL.md", "agents/openai.yaml"];
const MAX_FILE: u64 = 256 * 1024;
const MAX_MANIFEST: u64 = 16 * 1024 * 1024;
const PROVENANCE: &str = "sidefolk-skill-backups/manifest.json";
static NEXT: AtomicU64 = AtomicU64::new(0);

#[derive(Default)]
pub struct SkillSetupState { busy: Arc<AtomicBool> }
struct Busy(Arc<AtomicBool>);
impl Drop for Busy { fn drop(&mut self) { self.0.store(false, Ordering::SeqCst); } }

#[derive(Debug, Serialize)]
pub struct Outcome {
    /// installed | unchanged | cancelled. Errors never produce an installed outcome.
    pub status: &'static str,
    pub files: Vec<PathBuf>,
    pub backups: Vec<PathBuf>,
}

/// Explicit resources keep tests independent of bundled content or real agent profiles.
pub struct Resources<'a> { pub skill: &'a str, pub metadata: &'a str }
struct File {
    path: PathBuf,
    backup: PathBuf,
    before: Option<Vec<u8>>,
    after: Vec<u8>,
}
impl File { fn changed(&self) -> bool { self.before.as_deref() != Some(self.after.as_slice()) } }

/// A read-only preview. Call install only after the user confirms this exact plan.
pub struct Plan {
    files: Vec<File>, backup_dir: PathBuf, profile: PathBuf,
    manifest_before: Option<Vec<u8>>, manifest: Manifest,
}
#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Manifest { version: u8, files: Vec<Provenance> }
#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Provenance {
    name: String,
    /// Relative to sidefolk-skill-backups, restricted to <numeric-stamp>/<managed-name>.
    original: Option<String>,
    original_bytes: Option<Vec<u8>>,
    last: String,
    /// Write-ahead ownership for an interrupted update; cleared after both writes finish.
    previous: Option<String>,
}

fn manifest(profile: &Path) -> io::Result<(Option<Vec<u8>>, Manifest)> {
    let bytes = read_limit(&profile.join(PROVENANCE), MAX_MANIFEST)?;
    let value = match &bytes {
        Some(bytes) => serde_json::from_slice::<Manifest>(bytes).map_err(io::Error::other)?,
        None => Manifest { version:1, files:vec![] },
    };
    if value.version != 1 || value.files.len() > 2 { return Err(fail("Unsupported skill provenance.")); }
    let mut seen = std::collections::HashSet::new();
    for entry in &value.files {
        if !MANAGED.contains(&entry.name.as_str()) || !seen.insert(&entry.name)
            || entry.original.is_some() != entry.original_bytes.is_some()
            || entry.original_bytes.as_ref().is_some_and(|b| b.len() as u64 > MAX_FILE)
            || entry.last.len() as u64 > MAX_FILE || entry.previous.as_ref().is_some_and(|s| s.len() as u64 > MAX_FILE) {
            return Err(fail("Invalid skill provenance entry."));
        }
        if let Some(original) = &entry.original {
            let suffix = format!("/{}", entry.name);
            let stamp = original.strip_suffix(&suffix).ok_or_else(|| fail("Invalid skill backup path."))?;
            if stamp.is_empty() || !stamp.bytes().all(|c| c.is_ascii_digit() || c == b'-') {
                return Err(fail("Skill backup path is outside the managed allowlist."));
            }
            safe(&profile.join("sidefolk-skill-backups").join(original), true)?;
        }
    }
    Ok((bytes, value))
}
fn encode(value: &Manifest) -> io::Result<Vec<u8>> {
    let bytes = serde_json::to_vec(value).map_err(io::Error::other)?;
    if bytes.len() as u64 > MAX_MANIFEST { return Err(fail("Skill provenance exceeds its size limit.")); }
    Ok(bytes)
}

/// Explicit-path uninstall entry point. Never resolves HOME or runs an agent CLI.
#[derive(Debug, Default, Serialize)]
pub struct RestoreOutcome { pub restored: Vec<PathBuf>, pub conflicts: Vec<String> }
pub fn restore(profile: &Path) -> io::Result<RestoreOutcome> {
    safe(profile, false)?;
    let (before, mut state) = manifest(profile)?;
    if before.is_none() { return Ok(RestoreOutcome::default()); }
    let mut outcome = RestoreOutcome::default();
    let mut remaining = Vec::new();
    for entry in &state.files {
        let path = profile.join("skills/sidefolk").join(&entry.name);
        let result = (|| {
            if read_limit(&profile.join(PROVENANCE), MAX_MANIFEST)? != before { return Err(fail("Skill provenance changed; retry.")); }
            let original = match &entry.original {
                Some(relative) => {
                    let bytes = read(&profile.join("sidefolk-skill-backups").join(relative))?.ok_or_else(|| fail("Original skill backup is missing."))?;
                    if Some(&bytes) != entry.original_bytes.as_ref() { return Err(fail("Original skill backup changed; preserved current file.")); }
                    Some(bytes)
                },
                None => None,
            };
            let current = read(&path)?;
            // Idempotent after a crash between restoration and the provenance commit.
            if current == original { return Ok(()); }
            let owned = current.as_deref().is_some_and(|bytes| bytes == entry.last.as_bytes()
                || entry.previous.as_ref().is_some_and(|s| bytes == s.as_bytes()));
            if !owned { return Err(fail("Managed file was edited or removed; preserved.")); }
            match original {
                Some(bytes) => atomic(&path, current.as_deref(), &bytes, MAX_FILE)?,
                None => {
                    if read(&path)? != current { return Err(fail("Skill file changed during restoration.")); }
                    fs::remove_file(&path)?;
                    sync_dir(path.parent().unwrap())?;
                }
            }
            Ok(())
        })();
        match result {
            Ok(()) => outcome.restored.push(path),
            Err(e) => { outcome.conflicts.push(format!("{}: {e}", path.display())); remaining.push(entry.clone()); }
        }
    }
    state.files = remaining;
    atomic(&profile.join(PROVENANCE), before.as_deref(), &encode(&state)?, MAX_MANIFEST)?;
    Ok(outcome)
}
fn fail(message: impl Into<String>) -> io::Error { io::Error::other(message.into()) }
fn unique() -> String {
    let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_nanos();
    format!("{stamp}-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed))
}

/// Check every existing component; canonicalizing would silently follow a symlink instead.
fn safe(path: &Path, file: bool) -> io::Result<()> {
    if !path.is_absolute() || path.components().any(|p| matches!(p, Component::ParentDir | Component::CurDir)) {
        return Err(fail("Skill paths must be absolute, without parent traversal."));
    }
    let mut current = PathBuf::new();
    for part in path.components() {
        current.push(part.as_os_str());
        match fs::symlink_metadata(&current) {
            Ok(meta) => {
                let leaf = current == path && file;
                if meta.file_type().is_symlink() || (leaf && !meta.is_file()) || (!leaf && !meta.is_dir()) {
                    return Err(fail(format!("Unsafe skill path: {}", current.display())));
                }
                #[cfg(unix)]
                if leaf {
                    use std::os::unix::fs::MetadataExt;
                    if meta.nlink() != 1 { return Err(fail(format!("Refusing linked skill file: {}", current.display()))); }
                }
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => return Err(e),
        }
    }
    Ok(())
}
fn read(path: &Path) -> io::Result<Option<Vec<u8>>> { read_limit(path, MAX_FILE) }
fn read_limit(path: &Path, limit: u64) -> io::Result<Option<Vec<u8>>> {
    safe(path, true)?;
    let file = match fs::File::open(path) {
        Ok(file) => file,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(e),
    };
    let mut bytes = Vec::new();
    file.take(limit + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > limit { return Err(fail("Existing skill file exceeds the safe backup limit.")); }
    Ok(Some(bytes))
}
fn mkdir(path: &Path) -> io::Result<()> {
    safe(path, false)?;
    if path.is_dir() { return Ok(()); }
    if let Some(parent) = path.parent() { mkdir(parent)?; }
    let mut builder = fs::DirBuilder::new();
    #[cfg(unix)]
    { use std::os::unix::fs::DirBuilderExt; builder.mode(0o700); }
    match builder.create(path) {
        Ok(()) => path.parent().map_or(Ok(()), sync_dir),
        Err(e) if e.kind() == io::ErrorKind::AlreadyExists => safe(path, false),
        Err(e) => Err(e),
    }
}
fn write_new(path: &Path, bytes: &[u8]) -> io::Result<()> {
    safe(path, true)?;
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    { use std::os::unix::fs::OpenOptionsExt; options.mode(0o600); }
    let mut file = options.open(path)?;
    file.write_all(bytes)?;
    file.sync_all()
}
fn sync_dir(path: &Path) -> io::Result<()> {
    #[cfg(unix)]
    { fs::File::open(path)?.sync_all()?; }
    #[cfg(not(unix))]
    let _ = path;
    Ok(())
}

fn atomic(path: &Path, before: Option<&[u8]>, bytes: &[u8], limit: u64) -> io::Result<()> {
    let parent = path.parent().ok_or_else(|| fail("Missing skill parent."))?;
    mkdir(parent)?;
    let temp = parent.join(format!(".sidefolk-{}.tmp", unique()));
    let result = (|| {
        write_new(&temp, bytes)?;
        if read_limit(path, limit)?.as_deref() != before { return Err(fail("Skill file changed during write.")); }
        safe(parent, false)?;
        fs::rename(&temp, path)?;
        sync_dir(parent)
    })();
    if result.is_err() { let _ = fs::remove_file(&temp); }
    result
}

impl Plan {
    /// Only these two names are managed, under the explicit profile. Nothing is written here.
    pub fn prepare(profile: &Path, resources: Resources<'_>) -> io::Result<Self> {
        safe(profile, false)?;
        if resources.skill.is_empty() || resources.metadata.is_empty()
            || resources.skill.len() as u64 > MAX_FILE || resources.metadata.len() as u64 > MAX_FILE {
            return Err(fail("Both bundled skill resources must be present and within the size limit."));
        }
        let (manifest_before, manifest) = manifest(profile)?;
        let target = profile.join("skills/sidefolk");
        let backup_dir = profile.join("sidefolk-skill-backups").join(unique());
        safe(&backup_dir, false)?;
        let mut files = Vec::new();
        for (name, bytes) in MANAGED.iter().zip([resources.skill.as_bytes(), resources.metadata.as_bytes()]) {
            let path = target.join(name);
            let backup = backup_dir.join(name);
            safe(&backup, true)?;
            files.push(File { before: read(&path)?, path, backup, after: bytes.to_vec() });
        }
        Ok(Self { files, backup_dir, profile:profile.into(), manifest_before, manifest })
    }

    pub fn message(&self) -> String {
        let mut lines = vec!["Install Sidefolk's skill for new agent sessions?".to_string()];
        for file in &self.files {
            let change = if !file.changed() { "Already current" } else if file.before.is_some() { "Replace" } else { "Create" };
            lines.push(format!("\n{change}: {}", file.path.display()));
            if file.changed() && file.before.is_some() { lines.push(format!("Exact backup first: {}", file.backup.display())); }
        }
        lines.push(format!("\nDurable restore provenance: {}", self.profile.join(PROVENANCE).display()));
        lines.push("\nOnly these two managed skill files change. Unrelated files stay. This does not connect MCP or change agent settings.".into());
        lines.join("\n")
    }

    fn check(&self) -> io::Result<()> {
        safe(&self.backup_dir, false)?;
        if read_limit(&self.profile.join(PROVENANCE), MAX_MANIFEST)? != self.manifest_before { return Err(fail("Skill provenance changed while confirmation was open. Please try again.")); }
        for file in &self.files {
            if read(&file.path)? != file.before {
                return Err(fail("A skill file changed while confirmation was open. Please try again."));
            }
            safe(&file.backup, true)?;
            if fs::symlink_metadata(&file.backup).is_ok() { return Err(fail("A backup path is already occupied. Please try again.")); }
        }
        Ok(())
    }

    /// Pure filesystem operation. Caller must obtain native confirmation of message() first.
    /// All overwritten files are backed up before the first replacement. A later failure may
    /// leave a partial install; the error retains the exact recovery folder, never success.
    pub fn install(mut self) -> io::Result<Outcome> {
        self.check()?;
        let mut outcome = Outcome { status:"unchanged", files:vec![], backups:vec![] };
        let result = (|| {
            for file in self.files.iter().filter(|f| f.changed() && f.before.is_some()) {
                mkdir(file.backup.parent().unwrap())?;
                write_new(&file.backup, file.before.as_ref().unwrap())?;
                sync_dir(file.backup.parent().unwrap())?;
                outcome.backups.push(file.backup.clone());
            }
            // Recheck the entire confirmed snapshot after backups and before any replacement.
            for file in &self.files {
                if read(&file.path)? != file.before { return Err(fail("Skill files changed during installation. Please try again.")); }
            }
            let mut provenance_changed = self.manifest.files.iter().any(|e| e.previous.is_some());
            for (name, file) in MANAGED.iter().zip(&self.files) {
                if !file.changed() { continue; }
                provenance_changed = true;
                if let Some(entry) = self.manifest.files.iter_mut().find(|e| e.name == *name) {
                    // Keep the first original, never a later installed version or user edit.
                    if entry.last != String::from_utf8_lossy(&file.after) {
                        entry.previous = Some(entry.last.clone());
                        entry.last = String::from_utf8(file.after.clone()).map_err(io::Error::other)?;
                    }
                } else {
                    let original = file.before.as_ref().map(|_| format!("{}/{}", self.backup_dir.file_name().unwrap().to_string_lossy(), name));
                    self.manifest.files.push(Provenance { name:(*name).into(), original, original_bytes:file.before.clone(),
                        last:String::from_utf8(file.after.clone()).map_err(io::Error::other)?, previous:None });
                }
            }
            let manifest_path = self.profile.join(PROVENANCE);
            let pending = encode(&self.manifest)?;
            // Provenance commits before replacements, so even an interrupted install is removable.
            if provenance_changed { atomic(&manifest_path, self.manifest_before.as_deref(), &pending, MAX_MANIFEST)?; }
            for file in self.files.iter().filter(|f| f.changed()) {
                atomic(&file.path, file.before.as_deref(), &file.after, MAX_FILE)?;
                outcome.files.push(file.path.clone());
            }
            if provenance_changed {
                for entry in &mut self.manifest.files { entry.previous = None; }
                atomic(&manifest_path, Some(&pending), &encode(&self.manifest)?, MAX_MANIFEST)?;
            }
            Ok(())
        })();
        result.map_err(|e: io::Error| fail(format!("Skill installation did not finish: {e}. Review the two skill files before retrying; backups, if created, are in {}.", self.backup_dir.display())))?;
        if !outcome.files.is_empty() { outcome.status = "installed"; }
        Ok(outcome)
    }
}

fn profile(agent: &str) -> io::Result<PathBuf> {
    let (key, default) = match agent { "claude" => ("CLAUDE_CONFIG_DIR", ".claude"), "codex" => ("CODEX_HOME", ".codex"), _ => return Err(fail("Choose Claude Code or Codex.")) };
    if let Some(path) = std::env::var_os(key) {
        if path.is_empty() { return Err(fail(format!("{key} is empty."))); }
        return Ok(PathBuf::from(path));
    }
    let home = std::env::var_os("HOME").filter(|p| !p.is_empty()).ok_or_else(|| fail("Home folder is unavailable."))?;
    Ok(PathBuf::from(home).join(default))
}

/// Wire only to an explicit Settings button; deliberately absent from MCP and tray dispatch.
#[tauri::command]
pub async fn install_sidefolk_skill(app: AppHandle, window: WebviewWindow, agent: String) -> Result<Outcome, String> {
    if !["preferences", "settings"].contains(&window.label()) { return Err("Open Settings to install the Sidefolk skill.".into()); }
    let busy = app.state::<SkillSetupState>().busy.clone();
    if busy.compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst).is_err() { return Err("A skill installation is already open.".into()); }
    let _guard = Busy(busy);
    let target = profile(&agent).map_err(|e| e.to_string())?;
    let plan = tauri::async_runtime::spawn_blocking(move || Plan::prepare(&target, Resources { skill:SKILL, metadata:METADATA }))
        .await.map_err(|e| e.to_string())?.map_err(|e| e.to_string())?;
    let message = plan.message();
    let (tx, rx) = tokio::sync::oneshot::channel();
    let handle = app.clone();
    app.run_on_main_thread(move || {
        handle.dialog().message(message).title("Install Sidefolk skill?")
            .buttons(MessageDialogButtons::OkCancelCustom("Install".into(), "Cancel".into()))
            .show(move |confirmed| { let _ = tx.send(confirmed); });
    }).map_err(|e| e.to_string())?;
    if !rx.await.map_err(|_| "The skill confirmation closed unexpectedly.".to_string())? {
        return Ok(Outcome { status:"cancelled", files:vec![], backups:vec![] });
    }
    tauri::async_runtime::spawn_blocking(move || plan.install()).await.map_err(|e| e.to_string())?.map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Temp(PathBuf);
    impl Temp {
        fn new() -> Self {
            // macOS /var and /tmp may be system symlinks; use their real temporary parent.
            let path = fs::canonicalize(std::env::temp_dir()).unwrap().join(format!("sidefolk-skill-test-{}", unique()));
            fs::create_dir(&path).unwrap();
            Self(path)
        }
        fn profile(&self) -> PathBuf { self.0.join("profile") }
    }
    impl Drop for Temp { fn drop(&mut self) { let _ = fs::remove_dir_all(&self.0); } }
    fn resources() -> Resources<'static> { Resources { skill:"---\nname: sidefolk\n---\nSkill\n", metadata:"interface:\n  display_name: Sidefolk\n" } }

    #[test]
    fn preview_is_read_only_and_names_exact_changes() {
        let temp = Temp::new();
        let plan = Plan::prepare(&temp.profile(), resources()).unwrap();
        assert!(!temp.profile().exists());
        let message = plan.message();
        for name in MANAGED { assert!(message.contains(&temp.profile().join("skills/sidefolk").join(name).display().to_string())); }
        assert!(message.contains("Create:"));
        assert!(!message.contains("Exact backup first:"));
    }

    #[test]
    fn creates_only_managed_files_and_reinstall_is_noop() {
        let temp = Temp::new();
        let profile = temp.profile();
        let target = profile.join("skills/sidefolk");
        mkdir(&target).unwrap();
        fs::write(target.join("user-notes.txt"), "keep me").unwrap();
        fs::write(profile.join("config.toml"), "unrelated").unwrap();
        let outcome = Plan::prepare(&profile, resources()).unwrap().install().unwrap();
        assert_eq!(outcome.status, "installed");
        assert_eq!(outcome.files.len(), 2);
        assert!(outcome.backups.is_empty());
        assert_eq!(fs::read(target.join("SKILL.md")).unwrap(), resources().skill.as_bytes());
        assert_eq!(fs::read(target.join("agents/openai.yaml")).unwrap(), resources().metadata.as_bytes());
        assert_eq!(fs::read_to_string(target.join("user-notes.txt")).unwrap(), "keep me");
        assert_eq!(fs::read_to_string(profile.join("config.toml")).unwrap(), "unrelated");
        let outcome = Plan::prepare(&profile, resources()).unwrap().install().unwrap();
        assert_eq!(outcome.status, "unchanged");
        assert!(outcome.files.is_empty() && outcome.backups.is_empty());
        assert!(profile.join(PROVENANCE).is_file());
    }

    #[test]
    fn backs_up_exact_bytes_before_replacing_and_keeps_old_backups() {
        let temp = Temp::new();
        let profile = temp.profile();
        let target = profile.join("skills/sidefolk");
        mkdir(&target.join("agents")).unwrap();
        let old = [b"old\r\n\xff\x00".as_slice(), b"old metadata\r\n".as_slice()];
        for (name, bytes) in MANAGED.iter().zip(old) { fs::write(target.join(name), bytes).unwrap(); }
        let plan = Plan::prepare(&profile, resources()).unwrap();
        let message = plan.message();
        for file in &plan.files { assert!(message.contains(&file.backup.display().to_string())); }
        let outcome = plan.install().unwrap();
        for (path, bytes) in outcome.backups.iter().zip(old) { assert_eq!(fs::read(path).unwrap(), bytes); }
        #[cfg(unix)] {
            use std::os::unix::fs::PermissionsExt;
            for path in &outcome.backups { assert_eq!(fs::metadata(path).unwrap().permissions().mode() & 0o777, 0o600); }
        }
        fs::write(target.join("SKILL.md"), "another version").unwrap();
        let next = Plan::prepare(&profile, resources()).unwrap().install().unwrap();
        assert_eq!(next.backups.len(), 1);
        assert_ne!(next.backups[0], outcome.backups[0]);
        assert_eq!(fs::read(&outcome.backups[0]).unwrap(), old[0]);
        assert_eq!(fs::read(&next.backups[0]).unwrap(), b"another version");
    }

    #[test]
    fn refuses_stale_confirmation_before_any_replacement() {
        let temp = Temp::new();
        let profile = temp.profile();
        let target = profile.join("skills/sidefolk");
        mkdir(&target.join("agents")).unwrap();
        fs::write(target.join("SKILL.md"), "old skill").unwrap();
        fs::write(target.join("agents/openai.yaml"), "old metadata").unwrap();
        let plan = Plan::prepare(&profile, resources()).unwrap();
        fs::write(target.join("agents/openai.yaml"), "user edit").unwrap();
        assert!(plan.install().is_err());
        assert_eq!(fs::read_to_string(target.join("SKILL.md")).unwrap(), "old skill");
        assert_eq!(fs::read_to_string(target.join("agents/openai.yaml")).unwrap(), "user edit");
        assert!(!profile.join("sidefolk-skill-backups").exists());
    }

    #[test]
    fn rejects_unsafe_shapes_and_occupied_backups() {
        let temp = Temp::new();
        assert!(Plan::prepare(Path::new("relative"), resources()).is_err());
        assert!(Plan::prepare(&temp.0.join("../escape"), resources()).is_err());
        let profile = temp.profile();
        let target = profile.join("skills/sidefolk");
        mkdir(&target.join("SKILL.md")).unwrap();
        assert!(Plan::prepare(&profile, resources()).is_err());
        fs::remove_dir(target.join("SKILL.md")).unwrap();
        fs::write(target.join("SKILL.md"), "old").unwrap();
        let plan = Plan::prepare(&profile, resources()).unwrap();
        let backup = plan.files[0].backup.clone();
        mkdir(backup.parent().unwrap()).unwrap();
        fs::write(&backup, "precious existing backup").unwrap();
        assert!(plan.install().is_err());
        assert_eq!(fs::read_to_string(backup).unwrap(), "precious existing backup");
        assert_eq!(fs::read_to_string(target.join("SKILL.md")).unwrap(), "old");
        assert!(!target.join("agents").exists());
    }

    #[cfg(unix)]
    #[test]
    fn refuses_symlinks_at_every_managed_level_and_after_preview() {
        use std::os::unix::fs::symlink;
        for relative in ["", "skills", "skills/sidefolk", "skills/sidefolk/SKILL.md", "skills/sidefolk/agents", "skills/sidefolk/agents/openai.yaml", "sidefolk-skill-backups"] {
            let temp = Temp::new();
            let external = temp.0.join("external");
            mkdir(&external).unwrap();
            let profile = temp.profile();
            let link = if relative.is_empty() { profile.clone() } else { profile.join(relative) };
            mkdir(link.parent().unwrap()).unwrap();
            symlink(&external, &link).unwrap();
            assert!(Plan::prepare(&profile, resources()).is_err(), "{relative}");
            assert!(fs::read_dir(external).unwrap().next().is_none());
        }
        let temp = Temp::new();
        let profile = temp.profile();
        let plan = Plan::prepare(&profile, resources()).unwrap();
        mkdir(&profile.join("skills")).unwrap();
        symlink(&temp.0, profile.join("skills/sidefolk")).unwrap();
        assert!(plan.install().is_err());
        assert!(!temp.0.join("SKILL.md").exists());
    }

    #[cfg(unix)]
    #[test]
    fn refuses_hard_links_and_releases_busy_on_early_exit() {
        let temp = Temp::new();
        let target = temp.profile().join("skills/sidefolk");
        mkdir(&target).unwrap();
        fs::write(temp.0.join("original"), "keep").unwrap();
        fs::hard_link(temp.0.join("original"), target.join("SKILL.md")).unwrap();
        assert!(Plan::prepare(&temp.profile(), resources()).is_err());
        assert_eq!(fs::read_to_string(temp.0.join("original")).unwrap(), "keep");
        let busy = Arc::new(AtomicBool::new(true));
        { let _guard = Busy(busy.clone()); }
        assert!(!busy.load(Ordering::SeqCst));
    }

    #[test]
    fn install_update_restore_preserves_the_first_original_and_unrelated_files() {
        let temp = Temp::new();
        let profile = temp.profile();
        let target = profile.join("skills/sidefolk");
        mkdir(&target).unwrap();
        let original = b"user skill\r\n\xff\x00";
        fs::write(target.join("SKILL.md"), original).unwrap();
        fs::write(target.join("unrelated.txt"), "keep").unwrap();
        let installed = Plan::prepare(&profile, resources()).unwrap().install().unwrap();
        let first_backup = installed.backups[0].clone();
        let initial = fs::read(&first_backup).unwrap();
        Plan::prepare(&profile, Resources { skill:"updated skill", metadata:"updated metadata" }).unwrap().install().unwrap();
        let (_, state) = manifest(&profile).unwrap();
        assert_eq!(state.files[0].original_bytes.as_deref(), Some(original.as_slice()));
        assert_eq!(state.files[0].last, "updated skill");
        assert!(state.files.iter().all(|e| e.previous.is_none()));
        let restored = restore(&profile).unwrap();
        assert!(restored.conflicts.is_empty());
        assert_eq!(restored.restored.len(), 2);
        assert_eq!(fs::read(target.join("SKILL.md")).unwrap(), original);
        assert!(!target.join("agents/openai.yaml").exists());
        assert_eq!(fs::read_to_string(target.join("unrelated.txt")).unwrap(), "keep");
        assert_eq!(fs::read(&first_backup).unwrap(), initial);
        assert!(manifest(&profile).unwrap().1.files.is_empty());
        assert!(restore(&profile).unwrap().restored.is_empty());
    }

    #[test]
    fn restore_preserves_edits_reports_conflicts_and_can_be_retried() {
        let temp = Temp::new();
        let profile = temp.profile();
        let target = profile.join("skills/sidefolk");
        Plan::prepare(&profile, resources()).unwrap().install().unwrap();
        fs::write(target.join("SKILL.md"), "user edit").unwrap();
        let outcome = restore(&profile).unwrap();
        assert_eq!(outcome.conflicts.len(), 1);
        assert_eq!(outcome.restored.len(), 1);
        assert_eq!(fs::read_to_string(target.join("SKILL.md")).unwrap(), "user edit");
        assert!(!target.join("agents/openai.yaml").exists());
        assert_eq!(manifest(&profile).unwrap().1.files.len(), 1);
        fs::write(target.join("SKILL.md"), resources().skill).unwrap();
        assert!(restore(&profile).unwrap().conflicts.is_empty());
        assert!(!target.join("SKILL.md").exists());
    }

    #[test]
    fn restore_rejects_changed_backup_and_allowlist_escape_without_writing() {
        let temp = Temp::new();
        let profile = temp.profile();
        let target = profile.join("skills/sidefolk");
        mkdir(&target).unwrap();
        fs::write(target.join("SKILL.md"), "original").unwrap();
        let result = Plan::prepare(&profile, resources()).unwrap().install().unwrap();
        fs::write(&result.backups[0], "changed backup").unwrap();
        assert_eq!(restore(&profile).unwrap().conflicts.len(), 1);
        assert_eq!(fs::read_to_string(target.join("SKILL.md")).unwrap(), resources().skill);
        let (_, mut state) = manifest(&profile).unwrap();
        let valid = encode(&state).unwrap();
        state.files[0].original = Some("../../outside".into());
        fs::write(profile.join(PROVENANCE), encode(&state).unwrap()).unwrap();
        assert!(restore(&profile).is_err());
        assert!(Plan::prepare(&profile, resources()).is_err());
        fs::write(profile.join(PROVENANCE), &valid).unwrap();
        state.files[0].name = "../unrelated".into();
        fs::write(profile.join(PROVENANCE), encode(&state).unwrap()).unwrap();
        assert!(restore(&profile).is_err());
        assert_eq!(fs::read_to_string(target.join("SKILL.md")).unwrap(), resources().skill);
    }

    #[test]
    fn write_ahead_manifest_recovers_partial_update() {
        let temp = Temp::new();
        let profile = temp.profile();
        let target = profile.join("skills/sidefolk");
        Plan::prepare(&profile, resources()).unwrap().install().unwrap();
        // Simulate a crash after provenance and the first updated file, before the second.
        let (_, mut state) = manifest(&profile).unwrap();
        for entry in &mut state.files { entry.previous = Some(entry.last.clone()); entry.last = "new version".into(); }
        fs::write(profile.join(PROVENANCE), encode(&state).unwrap()).unwrap();
        fs::write(target.join("SKILL.md"), "new version").unwrap();
        let outcome = restore(&profile).unwrap();
        assert!(outcome.conflicts.is_empty());
        assert_eq!(outcome.restored.len(), 2);
        assert!(!target.join("SKILL.md").exists());
        assert!(!target.join("agents/openai.yaml").exists());
    }

    #[cfg(unix)]
    #[test]
    fn restore_never_follows_managed_or_manifest_symlinks() {
        use std::os::unix::fs::symlink;
        let temp = Temp::new();
        let profile = temp.profile();
        let target = profile.join("skills/sidefolk");
        Plan::prepare(&profile, resources()).unwrap().install().unwrap();
        let external = temp.0.join("external");
        fs::write(&external, "keep").unwrap();
        fs::remove_file(target.join("SKILL.md")).unwrap();
        symlink(&external, target.join("SKILL.md")).unwrap();
        let outcome = restore(&profile).unwrap();
        assert_eq!(outcome.conflicts.len(), 1);
        assert!(fs::symlink_metadata(target.join("SKILL.md")).unwrap().file_type().is_symlink());
        fs::remove_file(profile.join(PROVENANCE)).unwrap();
        symlink(&external, profile.join(PROVENANCE)).unwrap();
        assert!(restore(&profile).is_err());
        assert_eq!(fs::read_to_string(external).unwrap(), "keep");
    }

}
