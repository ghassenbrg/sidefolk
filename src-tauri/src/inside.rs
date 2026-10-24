//! Terminals inside Sidefolk's window ("Inside Sidefolk" as the default terminal): sessions,
//! commands and resumed sessions run in the user's login shell on a pseudo-terminal here, and the
//! window draws them with xterm.js (src/dashboard/terminal.ts). Output is kept (the last
//! megabyte) so the window can close and open again without losing what was on screen.
use std::{
    collections::BTreeMap,
    io::{Read, Write},
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex, OnceLock,
    },
};

use portable_pty::{native_pty_system, Child, CommandBuilder, MasterPty, PtySize};
use serde::Serialize;
use tauri::{AppHandle, Emitter};

/// Output kept per terminal for a window that attaches later.
const KEEP: usize = 1024 * 1024;

struct Term {
    title: String,
    cwd: String,
    tty: Option<String>,
    writer: Mutex<Box<dyn Write + Send>>,
    master: Mutex<Box<dyn MasterPty + Send>>,
    child: Mutex<Box<dyn Child + Send + Sync>>,
    /// The last KEEP bytes of output, and how many bytes came out in all.
    kept: Mutex<Vec<u8>>,
    total: AtomicU64,
    alive: AtomicBool,
}

static APP: OnceLock<AppHandle> = OnceLock::new();
static TERMS: Mutex<BTreeMap<u32, Arc<Term>>> = Mutex::new(BTreeMap::new());
static NEXT: AtomicU64 = AtomicU64::new(1);

pub fn init(app: &AppHandle) {
    let _ = APP.set(app.clone());
}

fn term(id: u32) -> Result<Arc<Term>, String> {
    TERMS.lock().unwrap().get(&id).cloned().ok_or_else(|| "That terminal is closed.".into())
}

/// Starts the login shell in `cwd`, types `command` into it and shows it in the window.
pub fn open(cwd: &str, command: &str) -> Result<&'static str, String> {
    let app = APP.get().ok_or("Sidefolk isn't ready yet.")?;
    let pair = native_pty_system().openpty(PtySize { rows: 32, cols: 110, pixel_width: 0, pixel_height: 0 }).map_err(|e| e.to_string())?;
    let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".into());
    let mut cmd = CommandBuilder::new(&shell);
    cmd.arg("-l");
    cmd.cwd(cwd);
    cmd.env("TERM", "xterm-256color");
    cmd.env("COLORTERM", "truecolor");
    let child = pair.slave.spawn_command(cmd).map_err(|e| e.to_string())?;
    drop(pair.slave);
    let mut reader = pair.master.try_clone_reader().map_err(|e| e.to_string())?;
    let mut writer = pair.master.take_writer().map_err(|e| e.to_string())?;
    // "Open a terminal in api" has nothing to type.
    if command != "true" {
        writer.write_all(format!("{command}\n").as_bytes()).map_err(|e| e.to_string())?;
    }
    let id = NEXT.fetch_add(1, Ordering::Relaxed) as u32;
    let folder = std::path::Path::new(cwd).file_name().map(|f| f.to_string_lossy().into_owned()).unwrap_or_else(|| cwd.into());
    let first = command.split_whitespace().next().filter(|w| *w != "true").unwrap_or("shell");
    let term = Arc::new(Term {
        title: format!("{first} · {folder}"),
        cwd: cwd.into(),
        tty: pair.master.tty_name().map(|p| p.to_string_lossy().into_owned()),
        writer: Mutex::new(writer),
        master: Mutex::new(pair.master),
        child: Mutex::new(child),
        kept: Mutex::new(Vec::new()),
        total: AtomicU64::new(0),
        alive: AtomicBool::new(true),
    });
    TERMS.lock().unwrap().insert(id, term.clone());

    let handle = app.clone();
    std::thread::spawn(move || {
        let mut buf = [0u8; 16 * 1024];
        // A UTF-8 character split across reads waits for its other half.
        let mut pending: Vec<u8> = Vec::new();
        while let Ok(n) = reader.read(&mut buf) {
            if n == 0 {
                break;
            }
            pending.extend_from_slice(&buf[..n]);
            let valid = match std::str::from_utf8(&pending) {
                Ok(_) => pending.len(),
                Err(e) if e.error_len().is_none() => e.valid_up_to(),
                Err(_) => pending.len(),
            };
            let chunk: Vec<u8> = pending.drain(..valid).collect();
            {
                let mut kept = term.kept.lock().unwrap();
                kept.extend_from_slice(&chunk);
                if kept.len() > KEEP {
                    let cut = kept.len() - KEEP;
                    kept.drain(..cut);
                }
            }
            let end = term.total.fetch_add(chunk.len() as u64, Ordering::Relaxed) + chunk.len() as u64;
            let _ = handle.emit_to(crate::prefs::WINDOW, "pty-data", serde_json::json!({ "id": id, "data": String::from_utf8_lossy(&chunk), "end": end }));
        }
        term.alive.store(false, Ordering::Relaxed);
        let _ = handle.emit_to(crate::prefs::WINDOW, "pty-exit", id);
    });

    let handle = app.clone();
    let _ = app.run_on_main_thread(move || {
        let _ = crate::prefs::open_at(&handle, &format!("terminal:{id}"));
    });
    Ok("Sidefolk")
}

/// A new terminal from the window: a shell in `cwd`, or the home folder.
#[tauri::command]
pub async fn pty_open(cwd: Option<String>) -> Result<(), String> {
    let cwd = cwd.filter(|c| std::path::Path::new(c).is_dir()).or_else(|| std::env::var("HOME").ok()).ok_or("No home folder.")?;
    tauri::async_runtime::spawn_blocking(move || open(&cwd, "true")).await.map_err(|e| e.to_string())?.map(|_| ())
}

/// The inside terminal a session runs in, from its tty ("/dev/ttys004").
pub fn by_tty(tty: &str) -> Option<u32> {
    TERMS.lock().unwrap().iter().find(|(_, t)| t.alive.load(Ordering::Relaxed) && t.tty.as_deref() == Some(tty)).map(|(id, _)| *id)
}

#[derive(Serialize)]
pub struct Info {
    id: u32,
    title: String,
    cwd: String,
    alive: bool,
}

#[tauri::command]
pub fn pty_list() -> Vec<Info> {
    TERMS.lock().unwrap().iter().map(|(id, t)| Info { id: *id, title: t.title.clone(), cwd: t.cwd.clone(), alive: t.alive.load(Ordering::Relaxed) }).collect()
}

#[derive(Serialize)]
pub struct Attached {
    data: String,
    /// Bytes of output so far: events ending at or before this are already in `data`.
    end: u64,
    alive: bool,
}

/// What the terminal showed so far, for a window drawing it.
#[tauri::command]
pub fn pty_attach(id: u32) -> Result<Attached, String> {
    let t = term(id)?;
    let kept = t.kept.lock().unwrap();
    Ok(Attached { data: String::from_utf8_lossy(&kept).into_owned(), end: t.total.load(Ordering::Relaxed), alive: t.alive.load(Ordering::Relaxed) })
}

/// Keys the user typed.
#[tauri::command]
pub fn pty_write(id: u32, data: String) -> Result<(), String> {
    term(id)?.writer.lock().unwrap().write_all(data.as_bytes()).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn pty_resize(id: u32, cols: u16, rows: u16) -> Result<(), String> {
    term(id)?.master.lock().unwrap().resize(PtySize { rows: rows.max(2), cols: cols.max(10), pixel_width: 0, pixel_height: 0 }).map_err(|e| e.to_string())
}

/// Closes a terminal: its shell and what runs in it stop.
#[tauri::command]
pub fn pty_close(id: u32) -> Result<(), String> {
    let t = TERMS.lock().unwrap().remove(&id).ok_or("That terminal is already closed.")?;
    let _ = t.child.lock().unwrap().kill();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runs_a_command_in_a_login_shell_and_keeps_its_output() {
        let pair = native_pty_system().openpty(PtySize { rows: 24, cols: 80, pixel_width: 0, pixel_height: 0 }).unwrap();
        let mut cmd = CommandBuilder::new("/bin/sh");
        cmd.args(["-c", "echo sidefolk-inside"]);
        let mut child = pair.slave.spawn_command(cmd).unwrap();
        drop(pair.slave);
        let mut reader = pair.master.try_clone_reader().unwrap();
        let mut out = String::new();
        let _ = reader.read_to_string(&mut out);
        child.wait().unwrap();
        assert!(out.contains("sidefolk-inside"));
        assert!(pair.master.tty_name().is_some_and(|p| p.to_string_lossy().starts_with("/dev/tty")));
    }
}
