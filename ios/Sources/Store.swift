import Foundation
import SwiftUI
import UIKit

/// What the phone keeps: the server, the token and who it belongs to. The token lives in the
/// keychain; the rest is small enough for user defaults. The Mac keeps its own link separately, so
/// linking a phone never disturbs a computer.
struct PhoneLink: Codable, Equatable {
    var server: String
    var login: String
    var name: String?

    var profileURL: URL? { URL(string: "\(server)/u/\(login)") }
}

enum TokenStore {
    private static let service = "app.keyhop.ios"
    private static let account = "session"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    static func write(_ token: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = Data(token.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}

/// Everything the screens read. One place asks the website; the views only show what it holds.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var link: PhoneLink?
    @Published private(set) var season: CloudSeason?
    @Published private(set) var board: CloudBoard?
    @Published private(set) var quests: CloudQuests?
    @Published private(set) var loading = false
    @Published var problem: String?

    /// While a link is being approved in the browser.
    @Published private(set) var pending: CloudClient.LinkStart?

    private static let linkKey = "phoneLink"
    private var pollTask: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.linkKey),
           let saved = try? JSONDecoder().decode(PhoneLink.self, from: data), TokenStore.read() != nil {
            link = saved
        }
    }

    /// `--sample` fills the screens with made-up people, for trying the app out and for screenshots.
    /// It never reads a token and never reaches the website, the way the Mac app's sample mode works.
    init(sample: Void) {
        link = PhoneLink(server: "https://keyhop.example", login: "you", name: "You")
        season = CloudSeason(
            season: "2026-09", label: "September 2026", daysLeft: 17, over: false, players: 6,
            you: CloudSeason.You(rank: 3, tokens: 4_140_000_000,
                                 tier: CloudSeason.Tier(key: "platinum", name: "Platinum", division: 2),
                                 next: CloudSeason.Step(label: "Platinum I", tokens: 940_000_000)))
        quests = CloudQuests(
            quests: [
                CloudQuests.Quest(key: "today", name: "Get going", note: "Use any tool today.", period: "day", done: 1, target: 1, complete: true),
                CloudQuests.Quest(key: "two-tools", name: "Two tools", note: "Use two different tools today.", period: "day", done: 1, target: 2, complete: false),
                CloudQuests.Quest(key: "five-days", name: "Five days", note: "Use Keyhop on five days this week.", period: "week", done: 5, target: 5, complete: true),
                CloudQuests.Quest(key: "every-tool", name: "Every tool", note: "Use all three tools this week.", period: "week", done: 2, target: 3, complete: false),
            ],
            badges: [])
        let people: [(String, String?, Int, Bool)] = [
            ("mira", "Mira K.", 6_370_000_000, false),
            ("jonas", nil, 5_180_000_000, false),
            ("you", "You", 4_140_000_000, true),
            ("priya", "Priya", 3_500_000_000, false),
            ("tomas", nil, 2_030_000_000, false),
            ("alex", nil, 1_120_000_000, false),
        ]
        board = CloudBoard(period: "week", metric: "tokens", entries: people.enumerated().map { index, person in
            CloudBoard.Entry(rank: index + 1, login: person.0, name: person.1, avatarUrl: nil, isPublic: true,
                             tokens: person.2, cost: Double(person.2) / 1_000_000 * 3.1, requests: person.2 / 42_000,
                             activeDays: 6, tools: ["claude": person.2 / 2, "cursor": person.2 / 3, "codex": person.2 / 6],
                             isYou: person.3)
        })
    }

    private var client: CloudClient? {
        guard let link, let token = TokenStore.read() else { return nil }
        return CloudClient(server: link.server, token: token)
    }

    var isLinked: Bool { link != nil }

    func refresh() async {
        guard let client else { return }
        loading = true
        defer { loading = false }
        do {
            async let season = client.season(team: nil)
            async let board = client.leaderboard(period: "week", metric: "tokens", team: nil)
            async let quests = try? await client.quests()
            self.season = try await season
            self.board = try await board
            self.quests = await quests
            problem = nil
        } catch let error as CloudError where error.kind == .unlinked {
            unlink()
            problem = "This phone isn't linked anymore. Link it again."
        } catch {
            problem = error.localizedDescription
        }
    }

    /// The same flow the Mac uses: ask for a code, send it to the browser, then wait for approval.
    func startLink(server: String = "https://keyhop.app") async {
        problem = nil
        let client = CloudClient(server: server)
        do {
            let start = try await client.startLink(label: Self.deviceLabel)
            pending = start
            if let url = URL(string: start.verifyUrl) { await UIApplication.shared.open(url) }
            pollTask?.cancel()
            pollTask = Task { await self.waitForApproval(client, start: start, server: server) }
        } catch {
            problem = error.localizedDescription
        }
    }

    func cancelLink() {
        pollTask?.cancel()
        pollTask = nil
        pending = nil
    }

    private func waitForApproval(_ client: CloudClient, start: CloudClient.LinkStart, server: String) async {
        let expires = Date().addingTimeInterval(TimeInterval(start.expiresIn))
        defer { pending = nil }
        while Date() < expires {
            try? await Task.sleep(for: .seconds(max(start.interval, 2)))
            if Task.isCancelled { return }
            guard let result = try? await client.poll(start.deviceCode) else { continue }
            switch result {
            case .pending:
                continue
            case .expired:
                problem = "That code expired. Try linking again."
                return
            case .granted(let granted):
                TokenStore.write(granted.token)
                let saved = PhoneLink(server: server, login: granted.user.login, name: granted.user.name)
                UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.linkKey)
                link = saved
                await refresh()
                return
            }
        }
        problem = "That code expired. Try linking again."
    }

    func unlink() {
        cancelLink()
        TokenStore.clear()
        UserDefaults.standard.removeObject(forKey: Self.linkKey)
        link = nil
        season = nil
        board = nil
        quests = nil
    }

    /// How this phone shows up under Linked apps on the website.
    private static var deviceLabel: String {
        let name = UIDevice.current.name
        return name.isEmpty ? "Keyhop on iPhone" : "\(name) (iOS)"
    }
}
