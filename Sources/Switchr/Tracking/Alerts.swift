#if os(macOS)
import Foundation
import UserNotifications

/// Budget and limit notifications. A limit alert can carry a Switch button that moves the tool
/// to the saved account with the most room left.
@MainActor
final class Alerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Alerts()

    private let sentKey = "sentAlerts"
    private var sent: [String: Date]

    override init() {
        sent = (UserDefaults.standard.dictionary(forKey: "sentAlerts") as? [String: Date]) ?? [:]
        super.init()
    }

    /// Notifications need a bundle; debug runs of the bare binary skip them.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func configure() {
        guard let center else { return }
        center.delegate = self
        let switchAction = UNNotificationAction(identifier: "switch", title: "Switch", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "limit", actions: [switchAction], intentIdentifiers: [], options: []),
        ])
    }

    /// Posts once per `key`; keys include the window or period, so the next one alerts again.
    func post(key: String, title: String, body: String, switchTo account: UUID? = nil) {
        guard let center, sent[key] == nil else { return }
        sent[key] = Date()
        sent = sent.filter { $0.value > Date().addingTimeInterval(-40 * 86400) }
        UserDefaults.standard.set(sent, forKey: sentKey)

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let account {
                content.categoryIdentifier = "limit"
                content.userInfo = ["account": account.uuidString]
            }
            center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let target = (response.notification.request.content.userInfo["account"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor in
            if action == "switch", let target, let account = AccountStore.shared.accounts.first(where: { $0.id == target }) {
                AccountStore.shared.switchTo(account)
            }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
#endif
