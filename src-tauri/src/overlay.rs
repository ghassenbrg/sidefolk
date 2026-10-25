//! The overlay is one transparent window on a display's work area. The page lays out on the
//! whole work area but the window covers only the part with companions and cards (src/frame.ts),
//! so Mission Control previews and screen shares lose nothing else while it hides from
//! recordings. It ignores the mouse by default; the page turns mouse events back on only while
//! the cursor is over the pet or its speech bubble. The page cannot see the cursor while it
//! ignores events, so this module streams the cursor position to it.

use crate::bus::Shared;
use std::{
    sync::{Arc, Mutex},
    thread,
    time::Duration,
};

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, Monitor, PhysicalPosition, PhysicalSize, WebviewWindow};

pub const OVERLAY: &str = "overlay";
const CURSOR_INTERVAL: Duration = Duration::from_millis(33);
/// Cursor ticks between checks that the overlay still matches its display's work area.
const REFIT_EVERY: u32 = 30;

/// The work area the page lays out on (physical pixels) and the part the window covers, in
/// points from the area's top left.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Layout {
    origin: PhysicalPosition<i32>,
    size: PhysicalSize<u32>,
    scale: f64,
    frame: Rect,
}

#[derive(Serialize, Clone, Copy, Debug, PartialEq)]
pub struct Rect {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}

static LAYOUT: Mutex<Option<Layout>> = Mutex::new(None);

#[derive(Serialize)]
pub struct Area {
    width: f64,
    height: f64,
    frame: Rect,
}

impl Layout {
    fn points(&self) -> (f64, f64) {
        (self.size.width as f64 / self.scale, self.size.height as f64 / self.scale)
    }

    /// `frame` kept on the work area, at least one point wide and tall.
    fn clamp(&self, frame: Rect) -> Rect {
        let (w, h) = self.points();
        let x = frame.x.clamp(0.0, w - 1.0).round();
        let y = frame.y.clamp(0.0, h - 1.0).round();
        Rect { x, y, width: frame.width.round().clamp(1.0, w - x), height: frame.height.round().clamp(1.0, h - y) }
    }
}

/// The work area in points and the window's part of it, for a page that just loaded.
#[tauri::command]
pub fn overlay_area() -> Option<Area> {
    let layout = (*LAYOUT.lock().unwrap())?;
    let (width, height) = layout.points();
    Some(Area { width, height, frame: layout.frame })
}

/// Moves the window over `x, y, width, height` (points in the work area). Commands without
/// `async` run on the main thread, so position and size change in one pass.
#[tauri::command]
pub fn overlay_frame(app: AppHandle, x: f64, y: f64, width: f64, height: f64) -> tauri::Result<Rect> {
    let mut guard = LAYOUT.lock().unwrap();
    let Some(layout) = guard.as_mut() else {
        return Ok(Rect { x, y, width, height });
    };
    let frame = layout.clamp(Rect { x, y, width, height });
    let window = overlay(&app);
    let px = |v: f64| (v * layout.scale).round();
    window.set_position(PhysicalPosition::new(layout.origin.x + px(frame.x) as i32, layout.origin.y + px(frame.y) as i32))?;
    window.set_size(PhysicalSize::new(px(frame.width) as u32, px(frame.height) as u32))?;
    layout.frame = frame;
    Ok(frame)
}

#[cfg(target_os = "macos")]
#[repr(C)]
struct CGPoint {
    x: f64,
    y: f64,
}

#[cfg(target_os = "macos")]
#[link(name = "CoreGraphics", kind = "framework")]
unsafe extern "C" {
    fn CGEventSourceSecondsSinceLastEventType(state: i32, kind: u32) -> f64;
    fn CGEventCreate(source: *const std::ffi::c_void) -> *mut std::ffi::c_void;
    fn CGEventGetLocation(event: *const std::ffi::c_void) -> CGPoint;
}

#[cfg(target_os = "macos")]
#[link(name = "CoreFoundation", kind = "framework")]
unsafe extern "C" {
    fn CFRelease(cf: *const std::ffi::c_void);
}

/// Seconds since the last keyboard or mouse input in this login session; no permission needed.
#[cfg(target_os = "macos")]
pub fn idle_seconds() -> f64 {
    // Combined session state, any event type.
    unsafe { CGEventSourceSecondsSinceLastEventType(0, u32::MAX) }
}

/// Cursor in global points (top-left origin), read on the calling thread. Tauri's
/// `cursor_position` is a round trip through the main thread, and doing that 30 times a
/// second kept AppKit and WebKit busy (about 3% CPU with nothing on screen moving).
#[cfg(target_os = "macos")]
fn cursor_points(_: &AppHandle, _: f64) -> Option<(f64, f64)> {
    unsafe {
        let event = CGEventCreate(std::ptr::null());
        if event.is_null() {
            return None;
        }
        let point = CGEventGetLocation(event);
        CFRelease(event);
        Some((point.x, point.y))
    }
}

#[cfg(not(target_os = "macos"))]
fn cursor_points(app: &AppHandle, scale: f64) -> Option<(f64, f64)> {
    let cursor = app.cursor_position().ok()?;
    Some((cursor.x / scale, cursor.y / scale))
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
    window.set_content_protected(saved.hide_in_recordings)?;
    #[cfg(not(target_os = "macos"))]
    window.show()?;
    set_visible(app, shown(&saved))?;
    stream_cursor(app.clone());
    Ok(())
}

/// Whether the companion's overlay is on screen: not hidden by the user.
pub fn shown(settings: &crate::settings::Settings) -> bool {
    !settings.hidden
}

/// Shows or hides the overlay to match the settings.
pub fn apply_visibility(app: &AppHandle) -> tauri::Result<()> {
    let settings = app.state::<Arc<Shared>>().settings.lock().unwrap().value.clone();
    set_visible(app, shown(&settings))
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

/// Covers the whole work area; the page then shrinks the window to what it shows.
fn fit(window: &WebviewWindow, monitor: &Monitor) -> tauri::Result<()> {
    let area = monitor.work_area();
    let scale = monitor.scale_factor();
    let layout = Layout {
        origin: area.position,
        size: area.size,
        scale,
        frame: Rect { x: 0.0, y: 0.0, width: area.size.width as f64 / scale, height: area.size.height as f64 / scale },
    };
    *LAYOUT.lock().unwrap() = Some(layout);
    window.set_position(area.position)?;
    window.set_size(area.size)?;
    window
        .state::<Arc<Shared>>()
        .settings
        .lock()
        .unwrap()
        .update(|s| s.display = monitor.name().cloned())?;
    let (width, height) = layout.points();
    let _ = window.emit("overlay-resized", serde_json::json!({ "width": width, "height": height }));
    Ok(())
}

/// The work area changes when the Dock or menu bar hides, in full-screen Spaces, and when
/// display settings change. Keep the layout matched so the pet stands on the right floor.
fn refit_if_needed(window: &WebviewWindow) {
    let Ok(Some(monitor)) = window.current_monitor() else {
        return;
    };
    let area = monitor.work_area();
    let known = *LAYOUT.lock().unwrap();
    if known.is_none_or(|l| l.origin != area.position || l.size != area.size || l.scale != monitor.scale_factor()) {
        if cfg!(debug_assertions) {
            eprintln!("sidefolk: refit {known:?} -> {:?} {:?} {:?}", monitor.name(), area.position, area.size);
        }
        let _ = fit(window, &monitor);
    }
}

/// Sends the cursor in overlay CSS pixels whenever it moves, about 30 times a second.
fn stream_cursor(app: AppHandle) {
    thread::spawn(move || {
        let mut last = (f64::NAN, f64::NAN);
        let mut tick: u32 = 0;
        loop {
            thread::sleep(CURSOR_INTERVAL);
            let Some(window) = app.get_webview_window(OVERLAY) else {
                return;
            };
            if tick.is_multiple_of(REFIT_EVERY) {
                refit_if_needed(&window);
                #[cfg(target_os = "macos")]
                {
                    let idle = idle_seconds();
                    if idle.is_finite() && idle >= 0.0 {
                        let _ = window.emit("idle", idle);
                    }
                }
            }
            tick = tick.wrapping_add(1);
            // The window's origin in global points, read each tick: the page moves the window.
            let Some(layout) = *LAYOUT.lock().unwrap() else {
                continue;
            };
            let scale = layout.scale;
            let origin = (layout.origin.x as f64 / scale + layout.frame.x, layout.origin.y as f64 / scale + layout.frame.y);
            let Some(cursor) = cursor_points(&app, scale) else {
                continue;
            };
            // Relative to the window, like the page's pointer events; a moved window resends.
            let cursor = (cursor.0 - origin.0, cursor.1 - origin.1);
            if (cursor.0 - last.0).abs() < 0.25 && (cursor.1 - last.1).abs() < 0.25 {
                continue;
            }
            last = cursor;
            let _ = window.emit("cursor", cursor);
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frames_stay_on_the_work_area() {
        let layout = Layout {
            origin: PhysicalPosition::new(0, 50),
            size: PhysicalSize::new(2880, 1750),
            scale: 2.0,
            frame: Rect { x: 0.0, y: 0.0, width: 1440.0, height: 875.0 },
        };
        let r = |x, y, width, height| Rect { x, y, width, height };
        assert_eq!(layout.clamp(r(928.4, 628.0, 264.0, 247.0)), r(928.0, 628.0, 264.0, 247.0));
        assert_eq!(layout.clamp(r(-20.0, 700.0, 300.0, 400.0)), r(0.0, 700.0, 300.0, 175.0));
        assert_eq!(layout.clamp(r(1500.0, 0.0, 0.0, 10.0)), r(1439.0, 0.0, 1.0, 10.0));
    }
}
