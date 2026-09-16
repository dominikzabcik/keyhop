import Foundation
import UserNotifications

/// The phone's own alarm clock.
///
/// Everything Keyhop announces is scheduled here, on this device, against a moment it already knows:
/// when a limit turns over, the season's last evening, tonight. No server ever reaches this phone,
/// which is why the companion needs no push service and works from source.
@MainActor
enum Notifier {
    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks once. iOS answers a second ask with the standing decision rather than another prompt.
    @discardableResult
    static func authorize() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces everything pending with this plan, so a countdown that has moved never fires late.
    static func apply(_ alerts: [PlannedAlert]) async {
        let center = UNUserNotificationCenter.current()
        guard await status() == .authorized else { return center.removeAllPendingNotificationRequests() }
        let pending = await center.pendingNotificationRequests()
        let wanted = Set(alerts.map(\.id))
        let stale = pending.map(\.identifier).filter { !wanted.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }

        // One already scheduled is already right: its id carries the moment it fires.
        let known = Set(pending.map(\.identifier))
        for alert in alerts where !known.contains(alert.id) {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            let wait = alert.at.timeIntervalSinceNow
            guard wait > 0 else { continue }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger))
        }
    }

    static func clear() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
