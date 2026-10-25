//! The calendar heads-up: the companion reads the next few hours of the user's macOS calendars
//! (EventKit, read-only, after they allow it) and says a meeting is coming, with Join when the
//! event has a video link. Nothing leaves the Mac.
use serde::Serialize;

#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Event {
    /// Unique per occurrence: repeating events share an identifier, so the start is added.
    pub id: String,
    pub title: String,
    /// Unix milliseconds.
    pub start: u64,
    pub end: u64,
    pub location: String,
    /// A video-call link found in the event's location, notes or URL.
    pub link: Option<String>,
    pub calendar: String,
}

/// Hosts of video calls people join from a calendar event.
#[cfg_attr(not(feature = "calendar"), allow(dead_code))]
const CALL_HOSTS: [&str; 8] = ["zoom.us/", "meet.google.com/", "teams.microsoft.com/", "teams.live.com/", "webex.com/", "whereby.com/", "around.co/", "facetime.apple.com/"];

/// The first video-call link in some text ("Join: https://meet.google.com/abc-defg-hij").
#[cfg_attr(not(feature = "calendar"), allow(dead_code))]
fn call_link(text: &str) -> Option<String> {
    text.split(|c: char| c.is_whitespace() || "<>\"'()[]".contains(c))
        .filter(|t| t.starts_with("https://"))
        .map(|t| t.trim_end_matches(['.', ',', ';']))
        .find(|t| CALL_HOSTS.iter().any(|host| t.contains(host)))
        .map(String::from)
}

#[tauri::command]
pub fn calendar_status() -> String {
    #[cfg(all(target_os = "macos", feature = "calendar"))]
    return native::status().into();
    #[cfg(not(all(target_os = "macos", feature = "calendar")))]
    "unavailable".into()
}

/// Asks macOS for read access to calendars; the user answers in macOS's own dialog.
#[tauri::command]
pub async fn request_calendar() -> Result<String, String> {
    #[cfg(all(target_os = "macos", feature = "calendar"))]
    {
        tauri::async_runtime::spawn_blocking(native::request_blocking).await.map_err(|e| e.to_string())??;
        return Ok(native::status().into());
    }
    #[cfg(not(all(target_os = "macos", feature = "calendar")))]
    Err("The calendar heads-up comes in a later version.".into())
}

/// Events starting in the next `hours` (at most 24), soonest first; all-day and cancelled ones
/// are left out.
#[tauri::command]
pub async fn upcoming_events(hours: Option<u64>) -> Result<Vec<Event>, String> {
    #[cfg(all(target_os = "macos", feature = "calendar"))]
    return tauri::async_runtime::spawn_blocking(move || native::upcoming(hours.unwrap_or(3).min(24))).await.map_err(|e| e.to_string())?;
    #[cfg(not(all(target_os = "macos", feature = "calendar")))]
    {
        let _ = hours;
        Ok(vec![])
    }
}

#[cfg(all(target_os = "macos", feature = "calendar"))]
mod native {
    use super::*;
    use block2::RcBlock;
    use objc2::runtime::Bool;
    use objc2_event_kit::{EKAuthorizationStatus, EKEntityType, EKEventStatus, EKEventStore};
    use objc2_foundation::{NSDate, NSError};
    use std::sync::Mutex;

    pub fn status() -> &'static str {
        match unsafe { EKEventStore::authorizationStatusForEntityType(EKEntityType::Event) } {
            EKAuthorizationStatus::FullAccess => "allowed",
            EKAuthorizationStatus::Denied | EKAuthorizationStatus::Restricted | EKAuthorizationStatus::WriteOnly => "denied",
            _ => "notRequested",
        }
    }

    /// Blocks until the user answers macOS's dialog; the store stays alive until then.
    pub fn request_blocking() -> Result<(), String> {
        let (tx, rx) = std::sync::mpsc::channel();
        let tx = Mutex::new(Some(tx));
        let store = unsafe { EKEventStore::new() };
        let done = RcBlock::new(move |_granted: Bool, err: *mut NSError| {
            let result = unsafe { err.as_ref() }.map_or(Ok(()), |e| Err(e.localizedDescription().to_string()));
            if let Some(tx) = tx.lock().unwrap().take() {
                let _ = tx.send(result);
            }
        });
        unsafe { store.requestFullAccessToEventsWithCompletion(RcBlock::as_ptr(&done)) };
        let answer = rx.recv_timeout(std::time::Duration::from_secs(300)).map_err(|_| "No answer from macOS.".to_string())?;
        drop(store);
        answer
    }

    pub fn upcoming(hours: u64) -> Result<Vec<Event>, String> {
        if status() != "allowed" {
            return Err("Sidefolk can't read your calendars yet. Allow it in Settings → Reminders & calendar.".into());
        }
        let ms = |date: &NSDate| (date.timeIntervalSince1970() * 1000.0).max(0.0) as u64;
        let store = unsafe { EKEventStore::new() };
        let now = NSDate::now();
        let until = NSDate::dateWithTimeIntervalSinceNow(hours as f64 * 3600.0);
        let predicate = unsafe { store.predicateForEventsWithStartDate_endDate_calendars(&now, &until, None) };
        let now_ms = ms(&now);
        let mut events: Vec<Event> = unsafe { store.eventsMatchingPredicate(&predicate) }
            .iter()
            .filter(|e| unsafe { !e.isAllDay() && e.status() != EKEventStatus::Canceled })
            .map(|e| unsafe {
                let start = ms(&e.startDate());
                let location = e.location().map(|l| l.to_string()).unwrap_or_default();
                let notes = e.notes().map(|n| n.to_string()).unwrap_or_default();
                let url = e.URL().and_then(|u| u.absoluteString()).map(|u| u.to_string()).unwrap_or_default();
                Event {
                    id: format!("{}@{start}", e.eventIdentifier().map(|i| i.to_string()).unwrap_or_default()),
                    title: crate::bus::clip(&e.title().to_string(), 120),
                    start,
                    end: ms(&e.endDate()),
                    link: call_link(&format!("{url} {location} {notes}")),
                    location: crate::bus::clip(&location, 120),
                    calendar: e.calendar().map(|c| c.title().to_string()).unwrap_or_default(),
                }
            })
            .filter(|e| e.start >= now_ms.saturating_sub(5 * 60_000))
            .collect();
        events.sort_by_key(|e| e.start);
        Ok(events)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_video_links() {
        assert_eq!(call_link("Join: https://meet.google.com/abc-defg-hij.").as_deref(), Some("https://meet.google.com/abc-defg-hij"));
        assert_eq!(call_link("<https://acme.zoom.us/j/123?pwd=x>").as_deref(), Some("https://acme.zoom.us/j/123?pwd=x"));
        assert_eq!(call_link("Room 4 · https://example.com/agenda"), None);
        assert_eq!(call_link("http://zoom.us/j/1"), None);
    }
}
