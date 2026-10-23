//! The overlay is one transparent window covering a display's work area. It ignores the
//! mouse by default; the page turns mouse events back on only while the cursor is over
//! the pet or its speech bubble. The page cannot see the cursor while it ignores events,
//! so this module streams the cursor position to it.

use crate::bus::Shared;
use std::{sync::Arc, thread, time::Duration};

use tauri::{AppHandle, Emitter, Manager, Monitor, PhysicalPosition, WebviewWindow};

pub const OVERLAY: &str = "overlay";
const CURSOR_INTERVAL: Duration = Duration::from_millis(33);
/// Cursor ticks between checks that the overlay still matches its display's work area.
const REFIT_EVERY: u32 = 30;

#[cfg(target_os = "macos")]
#[link(name = "CoreGraphics", kind = "framework")]
unsafe extern "C" {
    fn CGEventSourceSecondsSinceLastEventType(state: i32, kind: u32) -> f64;
}

pub fn setup(app: &AppHandle) -> tauri::Result<()> {
    let window = overlay(app);
    let saved = app
        .state::<Arc<Shared>>()
        .settings
        .lock()
        .unwrap()
        .value
        .clone();
    let monitor = app.available_monitors()?.into_iter().find(|m| {
        saved
            .display
            .as_ref()
            .is_some_and(|name| m.name() == Some(name))
    });
    if let Some(monitor) = monitor {
        fit(&window, &monitor)?;
    } else {
        fit_to_cursor_display(app)?;
    }
    window.set_ignore_cursor_events(true)?;
    #[cfg(target_os = "macos")]
    crate::panel::install(&window)?;
    #[cfg(not(target_os = "macos"))]
    window.show()?;
    set_visible(app, !saved.hidden)?;
    stream_cursor(app.clone());
    Ok(())
}

pub fn overlay(app: &AppHandle) -> WebviewWindow {
    app.get_webview_window(OVERLAY)
        .expect("the overlay window is declared in tauri.conf.json")
}

/// Must run on the main thread on macOS, just like tray callbacks and setup.
pub fn set_visible(app: &AppHandle, visible: bool) -> tauri::Result<()> {
    #[cfg(target_os = "macos")]
    {
        use tauri_nspanel::ManagerExt;
        let panel = app
            .get_webview_panel(OVERLAY)
            .map_err(|e| tauri::Error::Io(std::io::Error::other(format!("Panel: {e:?}"))))?;
        if visible {
            panel.show();
        } else {
            panel.resign_key_window();
            panel.hide();
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        if visible {
            overlay(app).show()?;
        } else {
            overlay(app).hide()?;
        }
    }
    Ok(())
}

/// Keyboard focus for the bubble's text field, without activating the app on macOS.
pub fn set_typing(app: &AppHandle, typing: bool) {
    #[cfg(target_os = "macos")]
    crate::panel::set_typing(app, typing);
    #[cfg(not(target_os = "macos"))]
    if typing {
        let _ = overlay(app).set_focus();
    }
}

/// Covers the work area (no menu bar, no Dock) of the display under the cursor.
pub fn fit_to_cursor_display(app: &AppHandle) -> tauri::Result<()> {
    let cursor = app.cursor_position()?;
    let monitor = match app.monitor_from_point(cursor.x, cursor.y)? {
        Some(monitor) => monitor,
        None => match app.primary_monitor()? {
            Some(monitor) => monitor,
            None => return Ok(()),
        },
    };
    fit(&overlay(app), &monitor)
}

fn fit(window: &WebviewWindow, monitor: &Monitor) -> tauri::Result<()> {
    let area = monitor.work_area();
    window.set_position(area.position)?;
    window.set_size(area.size)?;
    window
        .state::<Arc<Shared>>()
        .settings
        .lock()
        .unwrap()
        .update(|s| s.display = monitor.name().cloned())?;
    let _ = window.emit("overlay-resized", ());
    Ok(())
}

/// The work area changes when the Dock or menu bar hides, in full-screen Spaces, and when
/// display settings change. Keep the overlay matched so the pet stands on the right floor.
fn refit_if_needed(window: &WebviewWindow) {
    let (Ok(Some(monitor)), Ok(position), Ok(size)) = (
        window.current_monitor(),
        window.outer_position(),
        window.outer_size(),
    ) else {
        return;
    };
    let area = monitor.work_area();
    if area.position != position || area.size != size {
        if cfg!(debug_assertions) {
            eprintln!(
                "sidefolk: refit {position:?} {size:?} -> {:?} {:?} {:?}",
                monitor.name(),
                area.position,
                area.size
            );
        }
        let _ = fit(window, &monitor);
    }
}

/// Sends the cursor in overlay CSS pixels whenever it moves, about 30 times a second.
fn stream_cursor(app: AppHandle) {
    thread::spawn(move || {
        let mut last = PhysicalPosition::new(f64::NAN, f64::NAN);
        let mut origin = PhysicalPosition::new(0, 0);
        let mut scale = 1.0;
        let mut tick: u32 = 0;
        loop {
            thread::sleep(CURSOR_INTERVAL);
            let Some(window) = app.get_webview_window(OVERLAY) else {
                return;
            };
            // The overlay only moves when it is refit, so its geometry is refreshed lazily.
            if tick % REFIT_EVERY == 0 {
                refit_if_needed(&window);
                #[cfg(target_os = "macos")]
                {
                    // Combined session state, any keyboard/mouse event; no capture permission.
                    let idle = unsafe { CGEventSourceSecondsSinceLastEventType(0, u32::MAX) };
                    if idle.is_finite() && idle >= 0.0 {
                        let _ = window.emit("idle", idle);
                    }
                }
                if let (Ok(position), Ok(factor)) = (window.inner_position(), window.scale_factor())
                {
                    origin = position;
                    scale = factor;
                }
            }
            tick = tick.wrapping_add(1);
            let Ok(cursor) = app.cursor_position() else {
                continue;
            };
            if (cursor.x - last.x).abs() < 0.5 && (cursor.y - last.y).abs() < 0.5 {
                continue;
            }
            last = cursor;
            let x = (cursor.x - origin.x as f64) / scale;
            let y = (cursor.y - origin.y as f64) / scale;
            let _ = window.emit("cursor", (x, y));
        }
    });
}
