//! The overlay is one transparent window covering a display's work area. It ignores the
//! mouse by default; the page turns mouse events back on only while the cursor is over
//! the pet or its speech bubble. The page cannot see the cursor while it ignores events,
//! so this module streams the cursor position to it.

use std::{thread, time::Duration};

use tauri::{AppHandle, Emitter, Manager, PhysicalPosition, WebviewWindow};

const OVERLAY: &str = "overlay";
const CURSOR_INTERVAL: Duration = Duration::from_millis(33);

pub fn setup(app: &AppHandle) -> tauri::Result<()> {
    let window = overlay(app);
    fit_to_cursor_display(app)?;
    window.set_ignore_cursor_events(true)?;
    window.show()?;
    stream_cursor(app.clone());
    Ok(())
}

fn overlay(app: &AppHandle) -> WebviewWindow {
    app.get_webview_window(OVERLAY)
        .expect("the overlay window is declared in tauri.conf.json")
}

/// Covers the work area (no menu bar, no Dock) of the display under the cursor.
pub fn fit_to_cursor_display(app: &AppHandle) -> tauri::Result<()> {
    let window = overlay(app);
    let cursor = app.cursor_position()?;
    let monitor = match app.monitor_from_point(cursor.x, cursor.y)? {
        Some(monitor) => monitor,
        None => match app.primary_monitor()? {
            Some(monitor) => monitor,
            None => return Ok(()),
        },
    };
    let area = monitor.work_area();
    window.set_position(area.position)?;
    window.set_size(area.size)?;
    let _ = window.emit("overlay-resized", ());
    Ok(())
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
            if tick % 30 == 0 {
                if let (Ok(position), Ok(factor)) = (window.inner_position(), window.scale_factor()) {
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
