//! macOS holds the coming reminders' alarms (up to 60, reminders.rs `queue`), so they fire with
//! Sidefolk quit. The companion handles reminders while running; a notification click opens that
//! reminder in the window.
use crate::reminders::Queued;
use serde::Serialize;
use std::sync::mpsc::Sender;

#[derive(Serialize)]
pub struct Status {
    permission: String,
    error: Option<String>,
}

#[tauri::command]
pub async fn notification_status() -> Result<Status, String> {
    #[cfg(target_os = "macos")]
    return native::status().await;
    #[cfg(not(target_os = "macos"))]
    Ok(Status {
        permission: "unavailable".into(),
        error: None,
    })
}

#[tauri::command]
pub async fn request_notifications(
    shared: tauri::State<'_, std::sync::Arc<crate::bus::Shared>>,
) -> Result<Status, String> {
    #[cfg(target_os = "macos")]
    native::request().await?;
    shared.reminders.reschedule();
    notification_status().await
}

pub fn install(app: &tauri::AppHandle) -> Option<Sender<Vec<Queued>>> {
    #[cfg(target_os = "macos")]
    return native::install(app);
    #[cfg(not(target_os = "macos"))]
    {
        let _ = app;
        None
    }
}

/// The alarm's identifier: one per occurrence, so a series holds several at once.
fn identifier((id, _, at): &Queued) -> String {
    format!("reminder-{id}@{at}")
}

#[cfg(target_os = "macos")]
mod native {
    use super::*;
    use block2::{DynBlock, RcBlock};
    use objc2::{
        AnyThread, DefinedClass, define_class, msg_send,
        rc::Retained,
        runtime::{Bool, ProtocolObject},
    };
    use objc2_foundation::{NSArray, NSBundle, NSError, NSObject, NSObjectProtocol, NSString};
    use objc2_user_notifications::*;
    use std::{
        cell::RefCell,
        collections::HashMap,
        ptr::NonNull,
        sync::{Mutex, mpsc},
        time::Duration,
    };

    static ERROR: Mutex<Option<String>> = Mutex::new(None);
    thread_local! { static DELEGATE: RefCell<Option<Retained<Delegate>>> = const { RefCell::new(None) }; }

    define_class!(
        // NSObject has no subclass requirements. Callbacks can arrive on Apple's queue;
        // the AppHandle is thread-safe and all window operations go onto the main thread.
        #[unsafe(super = NSObject)]
        #[ivars = tauri::AppHandle]
        struct Delegate;
        unsafe impl NSObjectProtocol for Delegate {}
        unsafe impl UNUserNotificationCenterDelegate for Delegate {
            #[unsafe(method(userNotificationCenter:willPresentNotification:withCompletionHandler:))]
            fn present(
                &self,
                _center: &UNUserNotificationCenter,
                _notification: &UNNotification,
                completion: &DynBlock<dyn Fn(UNNotificationPresentationOptions)>,
            ) {
                completion.call((UNNotificationPresentationOptions::empty(),));
            }
            #[unsafe(method(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:))]
            fn response(
                &self,
                _center: &UNUserNotificationCenter,
                response: &UNNotificationResponse,
                completion: &DynBlock<dyn Fn()>,
            ) {
                let id = response.notification().request().identifier().to_string();
                // "reminder-<id>@<when>": the reminder's id comes first.
                if let Some(id) = id.strip_prefix("reminder-").map(|rest| rest.split('@').next().unwrap_or(rest)) {
                    if id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
                        let app = self.ivars().clone();
                        let tab = format!("reminders:{id}");
                        let handle = app.clone();
                        let _ = app.run_on_main_thread(move || {
                            let _ = crate::prefs::open_at(&handle, &tab);
                        });
                    }
                }
                completion.call(());
            }
        }
    );

    fn available() -> bool {
        // UserNotifications raises an Objective-C exception for an unbundled CLI executable.
        NSBundle::mainBundle().bundleIdentifier().is_some()
    }

    pub fn install(app: &tauri::AppHandle) -> Option<Sender<Vec<Queued>>> {
        if !available() {
            return None;
        }
        let allocated = Delegate::alloc().set_ivars(app.clone());
        let delegate: Retained<Delegate> = unsafe { msg_send![super(allocated), init] };
        let center = UNUserNotificationCenter::currentNotificationCenter();
        center.setDelegate(Some(ProtocolObject::from_ref(&*delegate)));
        DELEGATE.with(|slot| *slot.borrow_mut() = Some(delegate));
        let (tx, rx) = mpsc::channel::<Vec<Queued>>();
        std::thread::spawn(move || {
            let center = UNUserNotificationCenter::currentNotificationCenter();
            let mut previous: HashMap<String, (String, u64)> = HashMap::new();
            // Reconcile persisted requests, including reminders deleted before a crash.
            let (tx, initial) = mpsc::channel();
            center.getPendingNotificationRequestsWithCompletionHandler(&RcBlock::new(
                move |requests: NonNull<NSArray<UNNotificationRequest>>| {
                    let ids = unsafe { requests.as_ref() }
                        .iter()
                        .map(|r| r.identifier().to_string())
                        .collect::<Vec<_>>();
                    let _ = tx.send(ids);
                },
            ));
            if let Ok(ids) = initial.recv_timeout(Duration::from_secs(5)) {
                for id in ids {
                    if id.starts_with("reminder-") {
                        previous.insert(id, (String::new(), 0));
                    }
                }
            }
            while let Ok(list) = rx.recv() {
                let next: HashMap<_, _> = list.iter().map(|q| (identifier(q), (q.1.clone(), q.2))).collect();
                let removed: Vec<_> = previous
                    .keys()
                    .filter(|id| !next.contains_key(*id))
                    .map(|id| NSString::from_str(id))
                    .collect();
                let removed = NSArray::from_retained_slice(&removed);
                center.removePendingNotificationRequestsWithIdentifiers(&removed);
                center.removeDeliveredNotificationsWithIdentifiers(&removed);
                previous.retain(|id, _| next.contains_key(id));
                let mut error = None;
                for (id, value) in next {
                    if previous.get(&id) == Some(&value) {
                        continue;
                    }
                    let content = UNMutableNotificationContent::new();
                    content.setTitle(&NSString::from_str("Sidefolk reminder"));
                    content.setBody(&NSString::from_str(&value.0));
                    content.setSound(Some(&UNNotificationSound::defaultSound()));
                    let seconds = value.1.saturating_sub(crate::journal::now_ms()) as f64 / 1000.0;
                    let trigger =
                        UNTimeIntervalNotificationTrigger::triggerWithTimeInterval_repeats(
                            seconds.max(1.0),
                            false,
                        );
                    let request = UNNotificationRequest::requestWithIdentifier_content_trigger(
                        &NSString::from_str(&id),
                        &content,
                        Some(&trigger),
                    );
                    let (tx, result) = mpsc::channel();
                    center.addNotificationRequest_withCompletionHandler(
                        &request,
                        Some(&RcBlock::new(move |err: *mut NSError| {
                            let error = unsafe { err.as_ref() }
                                .map(|e| e.localizedDescription().to_string());
                            let _ = tx.send(error);
                        })),
                    );
                    match result.recv_timeout(Duration::from_secs(5)) {
                        Ok(None) => {
                            previous.insert(id, value);
                        }
                        Ok(Some(message)) => error = Some(message),
                        Err(_) => {
                            error = Some("macOS did not confirm the reminder notification.".into())
                        }
                    }
                }
                if let Some(message) = &error {
                    eprintln!("sidefolk: notifications: {message}");
                }
                *ERROR.lock().unwrap() = error;
            }
        });
        Some(tx)
    }

    pub async fn status() -> Result<Status, String> {
        if !available() {
            return Ok(Status {
                permission: "unavailable".into(),
                error: None,
            });
        }
        let (tx, rx) = tokio::sync::oneshot::channel();
        let tx = Mutex::new(Some(tx));
        UNUserNotificationCenter::currentNotificationCenter()
            .getNotificationSettingsWithCompletionHandler(&RcBlock::new(
                move |settings: NonNull<UNNotificationSettings>| {
                    let permission = match unsafe { settings.as_ref() }.authorizationStatus() {
                        UNAuthorizationStatus::Authorized | UNAuthorizationStatus::Provisional => {
                            "allowed"
                        }
                        UNAuthorizationStatus::Denied => "denied",
                        _ => "notRequested",
                    };
                    if let Some(tx) = tx.lock().unwrap().take() {
                        let _ = tx.send(permission.to_string());
                    }
                },
            ));
        let permission = tokio::time::timeout(Duration::from_secs(5), rx)
            .await
            .map_err(|_| "Notification status timed out")?
            .map_err(|e| e.to_string())?;
        Ok(Status {
            permission,
            error: ERROR.lock().unwrap().clone(),
        })
    }

    pub async fn request() -> Result<(), String> {
        if !available() {
            return Err("Open the built Sidefolk.app to allow macOS notifications.".into());
        }
        let (tx, rx) = tokio::sync::oneshot::channel();
        let tx = Mutex::new(Some(tx));
        UNUserNotificationCenter::currentNotificationCenter()
            .requestAuthorizationWithOptions_completionHandler(
                UNAuthorizationOptions::Alert | UNAuthorizationOptions::Sound,
                &RcBlock::new(move |_granted: Bool, err: *mut NSError| {
                    let result = unsafe { err.as_ref() }
                        .map_or(Ok(()), |e| Err(e.localizedDescription().to_string()));
                    if let Some(tx) = tx.lock().unwrap().take() {
                        let _ = tx.send(result);
                    }
                }),
            );
        rx.await.map_err(|e| e.to_string())?
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn each_occurrence_has_its_own_alarm() {
        assert_eq!(identifier(&("r1-0".into(), "stretch".into(), 42)), "reminder-r1-0@42");
    }
}
