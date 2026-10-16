#if os(macOS)
import Foundation
@preconcurrency import UserNotifications
import AppKit

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

    /// Each offered hop names its account on the button, so each one has its own category.
    private var categories: [String: UNNotificationCategory] = [:]

    func configure() {
        guard let center else { return }
        center.delegate = self
        let later = UNNotificationAction(identifier: "later", title: "Later", options: [])
        let add = UNNotificationAction(identifier: "add", title: "Add a login", options: [.foreground])
        categories["limit"] = UNNotificationCategory(identifier: "limit", actions: [UNNotificationAction(identifier: "switch", title: "Hop", options: []), later], intentIdentifiers: [], options: [])
        categories["add"] = UNNotificationCategory(identifier: "add", actions: [add, later], intentIdentifiers: [], options: [])
        center.setNotificationCategories(Set(categories.values))
    }

    /// Posts once per `key`; keys include the window or period, so the next one alerts again.
    /// After KB-Notify: the title names the tool and its state, the subtitle names the account,
    /// the tool's mark rides along as the picture, and the buttons say where the hop goes.
    func post(key: String, title: String, body: String, switchTo account: UUID? = nil,
              subtitle: String? = nil, tool: String? = nil, switchName: String? = nil, offerAdd: Bool = false) {
        guard let center, sent[key] == nil else { return }
        sent[key] = Date()
        sent = sent.filter { $0.value > Date().addingTimeInterval(-40 * 86400) }
        UserDefaults.standard.set(sent, forKey: sentKey)

        var category: String?
        if account != nil {
            let id = switchName.map { "hop:\($0)" } ?? "limit"
            if categories[id] == nil, let name = switchName {
                categories[id] = UNNotificationCategory(identifier: id, actions: [
                    UNNotificationAction(identifier: "switch", title: "Hop to \(name)", options: []),
                    UNNotificationAction(identifier: "later", title: "Later", options: []),
                ], intentIdentifiers: [], options: [])
                center.setNotificationCategories(Set(categories.values))
            }
            category = id
        } else if offerAdd {
            category = "add"
        }
        let picture = tool.flatMap(Provider.init(rawValue:)).flatMap(Self.markFile)

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            if let subtitle { content.subtitle = subtitle }
            content.body = body
            content.sound = .default
            if let category { content.categoryIdentifier = category }
            var info: [String: String] = [:]
            if let account { info["account"] = account.uuidString }
            if let tool { info["tool"] = tool }
            content.userInfo = info
            if let picture, let attachment = try? UNNotificationAttachment(identifier: "mark", url: picture, options: nil) {
                content.attachments = [attachment]
            }
            center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
        }
    }

    /// The tool's mark as a picture: the glyph in white on a dark tile, written once per tool.
    /// The system moves an attachment's file, so each notification gets its own copy.
    private static func markFile(for provider: Provider) -> URL? {
        let size: CGFloat = 128
        guard let glyph = NSImage(data: Data(ProviderMarks.svg(for: provider).utf8)) else { return nil }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor(srgbRed: 0.09, green: 0.09, blue: 0.09, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28).fill()
            let tinted = NSImage(size: glyph.size, flipped: false) { inner in
                glyph.draw(in: inner)
                NSColor.white.set()
                inner.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: rect.insetBy(dx: 30, dy: 30))
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keyhop-mark-\(provider.rawValue)-\(UUID().uuidString).png")
        do { try png.write(to: url) } catch { return nil }
        return url
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let target = (response.notification.request.content.userInfo["account"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor in
            if action == "switch" || action == UNNotificationDefaultActionIdentifier && target != nil,
               let target, let account = AccountStore.shared.accounts.first(where: { $0.id == target }) {
                if action == "switch" { AccountStore.shared.switchTo(account) } else { AppWindow.show(section: "limits") }
            } else if action == "add" || action == UNNotificationDefaultActionIdentifier {
                AppWindow.show(section: action == "add" ? "limits" : nil)
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
