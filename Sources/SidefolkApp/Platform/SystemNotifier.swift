import AppKit
import SidefolkCore
import UserNotifications

/// macOS notifications for attention items when the companion can't show them (hidden, fullscreen,
/// quiet, critical), plus the reminder fallback scheduled when Sidefolk quits.
final class SystemNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// UNUserNotificationCenter crashes outside an app bundle (e.g. `swift run`).
    nonisolated static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    private let attention: AttentionCenter
    private var center: UNUserNotificationCenter? { Self.isAvailable ? UNUserNotificationCenter.current() : nil }
    private static let fallbackPrefix = "fallback."

    init(attention: AttentionCenter) {
        self.attention = attention
        super.init()
    }

    func configure() {
        guard let center else { return }
        center.delegate = self
        let actions = [
            UNNotificationAction(identifier: "done", title: String(localized: "Done")),
            UNNotificationAction(identifier: "snooze10", title: String(localized: "10 min")),
            UNNotificationAction(identifier: "tomorrow", title: String(localized: "Tomorrow")),
        ]
        let reminder = UNNotificationCategory(identifier: "reminder", actions: actions, intentIdentifiers: [])
        // A reminder that comes back within the hour: "Tomorrow" means little, stopping it means a lot.
        let repeating = UNNotificationCategory(identifier: "reminderRepeat", actions: [
            UNNotificationAction(identifier: "done", title: String(localized: "Done")),
            UNNotificationAction(identifier: "stop", title: String(localized: "Stop repeating")),
        ], intentIdentifiers: [])
        let generic = UNNotificationCategory(identifier: "generic", actions: [], intentIdentifiers: [])
        center.setNotificationCategories([reminder, repeating, generic])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        guard let center else { return .denied }
        return await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func show(_ item: AttentionItem, sound: Bool) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = item.title
        if let body = item.body { content.body = body }
        content.sound = sound ? .default : nil
        content.categoryIdentifier = item.refKind != "reminder" ? "generic"
            : item.actions.contains { $0.id == ReminderScheduler.ActionID.stop } ? "reminderRepeat" : "reminder"
        content.userInfo = ["attentionId": item.id]
        content.threadIdentifier = item.source
        center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: nil))
    }

    func withdraw(id: String) {
        center?.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// A report's value as a notification. Every reading of one report shares one identifier, so the new value
    /// replaces the last in Notification Center instead of piling up; it makes no sound.
    func showReport(_ reading: WatchReading) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = reading.title
        content.body = reading.value
        content.categoryIdentifier = "generic"
        content.threadIdentifier = "report"
        center.add(UNNotificationRequest(identifier: Self.reportPrefix + reading.watcherId, content: content, trigger: nil))
    }

    func withdrawReport(_ watcherId: String) {
        center?.removeDeliveredNotifications(withIdentifiers: [Self.reportPrefix + watcherId])
    }

    private static let reportPrefix = "report."

    /// Schedules system notifications for reminders due while Sidefolk is not running.
    func scheduleFallback(_ reminders: [(id: String, title: String, body: String?, date: Date)]) {
        guard let center else { return }
        for r in reminders.prefix(60) {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body ?? String(localized: "Sidefolk isn't running, so here's your reminder.")
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: r.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: Self.fallbackPrefix + r.id, content: content, trigger: trigger))
        }
    }

    /// While Sidefolk runs it delivers reminders itself; remove the fallbacks.
    func clearFallback() async {
        guard let center else { return }
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.fallbackPrefix) })
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["attentionId"] as? String else { return }
        let action: String? = switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier: "open"
        case UNNotificationDismissActionIdentifier: nil
        default: response.actionIdentifier
        }
        let attention = await MainActor.run { self.attention }
        await attention.respond(id: id, actionId: action)
    }
}
