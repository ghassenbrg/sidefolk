//! macOS: the overlay is turned into a non-activating NSPanel so clicking or dragging the
//! pet never takes focus from the app you are using. It joins every Space, including
//! full-screen ones, and becomes the key window only while you type in its bubble.

use tauri::{AppHandle, WebviewWindow};
use tauri_nspanel::{
    CollectionBehavior, ManagerExt, PanelLevel, StyleMask, WebviewWindowExt, tauri_panel,
};

tauri_panel! {
    panel!(OverlayPanel {
        config: {
            can_become_key_window: true,
            can_become_main_window: false,
            is_floating_panel: true
        }
    })
}

pub fn install(window: &WebviewWindow) -> tauri::Result<()> {
    let panel = window.to_panel::<OverlayPanel>()?;
    if let Err(error) = panel.add_style_mask(StyleMask::empty().nonactivating_panel().into()) {
        eprintln!("sidefolk: overlay could not become non-activating: {error:?}");
    }
    panel.set_level(PanelLevel::Floating.value());
    panel.set_floating_panel(true);
    // Panels hide when their app deactivates by default; the pet must stay.
    panel.set_hides_on_deactivate(false);
    // Clicks on the pet should not make it key; the bubble's text field still can.
    panel.set_becomes_key_only_if_needed(true);
    panel.set_collection_behavior(
        CollectionBehavior::new()
            .can_join_all_spaces()
            .full_screen_auxiliary()
            .stationary()
            .ignores_cycle()
            .into(),
    );
    panel.show();
    Ok(())
}

/// Takes keyboard focus for the bubble's text field without activating Sidefolk, then gives it
/// back so keystrokes return to the app you were in.
pub fn set_typing(app: &AppHandle, typing: bool) {
    let handle = app.clone();
    let _ = app.run_on_main_thread(move || {
        let Ok(panel) = handle.get_webview_panel(crate::overlay::OVERLAY) else {
            return;
        };
        if typing {
            panel.make_key_window();
        } else {
            panel.resign_key_window();
        }
    });
}

/// Dev check: which app is frontmost, whether the overlay holds keyboard focus, and whether
/// macOS considers it on the active Space and visible.
pub fn focus_report(app: &AppHandle) -> String {
    let (tx, rx) = std::sync::mpsc::channel();
    let handle = app.clone();
    let _ = app.run_on_main_thread(move || {
        use tauri_nspanel::objc2_app_kit::NSWorkspace;
        let frontmost = NSWorkspace::sharedWorkspace()
            .frontmostApplication()
            .and_then(|a| a.bundleIdentifier())
            .map(|id| id.to_string())
            .unwrap_or_else(|| "unknown".into());
        let Ok(panel) = handle.get_webview_panel(crate::overlay::OVERLAY) else {
            let _ = tx.send(format!("frontmost={frontmost} overlay missing"));
            return;
        };
        let window = panel.as_panel();
        let visible = window
            .occlusionState()
            .contains(tauri_nspanel::objc2_app_kit::NSWindowOcclusionState::Visible);
        let screen = window
            .screen()
            .map(|s| s.localizedName().to_string())
            .unwrap_or_else(|| "none".into());
        let _ = tx.send(format!(
            "frontmost={frontmost} overlay_key={} active_space={} unoccluded={visible} screen={screen:?}",
            window.isKeyWindow(),
            window.isOnActiveSpace(),
        ));
    });
    rx.recv_timeout(std::time::Duration::from_secs(1))
        .unwrap_or_else(|_| "focus report timed out".into())
}

/// Hook handlers run off the main thread; NSWorkspace must still be queried on it.
pub async fn frontmost_bundle(app: &AppHandle) -> Option<String> {
    let (tx, rx) = tokio::sync::oneshot::channel();
    app.run_on_main_thread(move || {
        use tauri_nspanel::objc2_app_kit::NSWorkspace;
        let id = NSWorkspace::sharedWorkspace()
            .frontmostApplication()
            .and_then(|app| app.bundleIdentifier())
            .map(|id| id.to_string());
        let _ = tx.send(id);
    })
    .ok()?;
    tokio::time::timeout(std::time::Duration::from_secs(1), rx)
        .await
        .ok()?
        .ok()?
}
