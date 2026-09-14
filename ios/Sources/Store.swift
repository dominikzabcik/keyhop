import Foundation
import Security
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
    private static let tokenAccount = "session"

    static func read(account: String = tokenAccount) -> String? {
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

    static func write(_ token: String, account: String = tokenAccount) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let value: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(value) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func clear(account: String = tokenAccount) throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
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
        } else {
            UserDefaults.standard.removeObject(forKey: Self.linkKey)
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
            badges: [
                CloudQuests.Badge(key: "first-hop", name: "First hop", note: "Join your first season.", earned: true, day: "2026-09-01"),
                CloudQuests.Badge(key: "billion", name: "One billion", note: "Use one billion tokens in a season.", earned: true, day: "2026-09-08"),
                CloudQuests.Badge(key: "podium", name: "Podium", note: "Finish a week in the top three.", earned: false, day: nil),
            ])
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
            async let profile = client.me()
            async let season = client.season(team: nil)
            async let board = client.leaderboard(period: "week", metric: "tokens", team: nil)
            async let quests = try? await client.quests()
            let (updatedProfile, updatedSeason, updatedBoard) = try await (profile, season, board)
            if var saved = link {
                saved.login = updatedProfile.login
                saved.name = updatedProfile.name
                UserDefaults.standard.set(try JSONEncoder().encode(saved), forKey: Self.linkKey)
                link = saved
            }
            self.season = updatedSeason
            self.board = updatedBoard
            self.quests = await quests
            problem = nil
        } catch let error as CloudError where error.kind == .unlinked {
            try? clearLocalLink()
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
            let start = try await client.startLink(label: Self.deviceLabel, readOnly: true)
            guard let verificationURL = Self.verificationURL(start.verifyUrl, server: server) else {
                throw CloudError(kind: .server, message: "Keyhop cloud returned an unsafe linking address.")
            }
            pending = start
            guard await UIApplication.shared.open(verificationURL) else {
                throw CloudError(kind: .server, message: "Couldn't open the linking page.")
            }
            pollTask?.cancel()
            pollTask = Task { await self.waitForApproval(client, start: start, server: server) }
        } catch {
            pending = nil
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
                let saved = PhoneLink(server: server, login: granted.user.login, name: granted.user.name)
                do {
                    let metadata = try JSONEncoder().encode(saved)
                    try TokenStore.write(granted.token)
                    UserDefaults.standard.set(metadata, forKey: Self.linkKey)
                    link = saved
                } catch {
                    problem = "Couldn't protect this phone's link: \(error.localizedDescription)"
                    return
                }
                await refresh()
                return
            }
        }
        problem = "That code expired. Try linking again."
    }

    func unlink() async {
        cancelLink()
        do {
            if let client { try await client.unlink() }
            try clearLocalLink()
            problem = nil
        } catch {
            problem = "Couldn't finish unlinking this phone: \(error.localizedDescription)"
        }
    }

    private func clearLocalLink() throws {
        var keychainError: Error?
        do {
            try TokenStore.clear()
        } catch {
            keychainError = error
        }
        UserDefaults.standard.removeObject(forKey: Self.linkKey)
        link = nil
        season = nil
        board = nil
        quests = nil
        if let keychainError { throw keychainError }
    }

    static func verificationURL(_ value: String, server: String) -> URL? {
        guard let url = URL(string: value), let origin = URL(string: server),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              scheme == origin.scheme?.lowercased(),
              url.host?.lowercased() == origin.host?.lowercased(), url.port == origin.port else { return nil }
        return url
    }

    private static let deviceLabel = "Keyhop on iPhone"
}
