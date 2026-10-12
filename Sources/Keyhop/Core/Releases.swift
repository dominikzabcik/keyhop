import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

struct ReleaseInfo: Equatable, Sendable {
    let version: String
    let page: URL
    let assets: [String: URL]
    /// True for a beta, published as a GitHub prerelease.
    var prerelease: Bool = false
}

/// Which releases a computer follows. Stable is the tested releases from main. Beta is every
/// release, prereleases built from the next version included, so it always runs the newest build
/// there is. The choice is saved with Keyhop's data so the app, the tray and the command agree.
enum UpdateChannel: String, Codable, CaseIterable, Sendable {
    case stable, beta

    var title: String { self == .stable ? "Stable" : "Beta" }

    var note: String {
        switch self {
        case .stable: "Tested releases. The default."
        case .beta: "Nightly builds of the next version, a day or a week ahead of Stable. Might have rough edges."
        }
    }

    static var url: URL { Platform.dataDirectory.appendingPathComponent("update.json") }

    private struct Saved: Codable {
        let channel: UpdateChannel
    }

    /// The saved choice, if one was made.
    static var saved: UpdateChannel? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(Saved.self, from: data))?.channel
    }

    /// The saved choice, or the channel the running build came from: a beta follows Beta until told otherwise.
    static var current: UpdateChannel { saved ?? (AppVersion.isPrerelease ? .beta : .stable) }

    static func save(_ channel: UpdateChannel) throws {
        try FileManager.default.createDirectory(at: Platform.dataDirectory, withIntermediateDirectories: true)
        try Files.writeAtomically(JSONEncoder().encode(Saved(channel: channel)), to: url)
    }

    static func parse(_ word: String) -> UpdateChannel? {
        switch word.lowercased() {
        case "stable", "prod", "production", "release": .stable
        case "beta", "nightly", "preview", "insiders": .beta
        default: nil
        }
    }
}

/// Reading this repository's GitHub releases, shared by the macOS updater and `keyhop update`.
enum Releases {
    static let repository = "dominikzabcik/keyhop"

    /// The newest release on a channel: Stable reads GitHub's latest release, which never is a
    /// prerelease; Beta reads the recent releases and takes the newest version of all of them.
    static func latest(channel: UpdateChannel = .current) async throws -> ReleaseInfo {
        let path = channel == .stable ? "releases/latest" : "releases?per_page=30"
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/\(path)")!, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("keyhop/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        let (data, status) = try await HTTP.send(request)
        guard status == 200 else { throw KeyhopError("GitHub didn't return a release (HTTP \(status)).") }
        if channel == .stable {
            guard let body = JSON.object(data), let release = release(from: body) else { throw KeyhopError("GitHub didn't return a release.") }
            return release
        }
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]], let newest = newest(in: list) else {
            throw KeyhopError("GitHub didn't return a release.")
        }
        return newest
    }

    /// One release from GitHub's JSON. Drafts are never offered.
    static func release(from body: [String: Any]) -> ReleaseInfo? {
        guard body["draft"] as? Bool != true,
              let tag = body["tag_name"] as? String,
              let page = (body["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        var assets: [String: URL] = [:]
        for asset in body["assets"] as? [[String: Any]] ?? [] {
            if let name = asset["name"] as? String, let url = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)) {
                assets[name] = url
            }
        }
        return ReleaseInfo(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, page: page, assets: assets,
                           prerelease: body["prerelease"] as? Bool ?? false)
    }

    /// The newest version in a list of releases, betas and stable ones alike.
    static func newest(in list: [[String: Any]]) -> ReleaseInfo? {
        list.compactMap(release(from:)).max { isNewer($1.version, than: $0.version) }
    }

    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 180)
        request.setValue("keyhop/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        let (data, status) = try await HTTP.send(request)
        guard status == 200 else { throw KeyhopError("The download failed (HTTP \(status)).") }
        return data
    }

    /// Semantic version order: numbers compare as numbers (0.10.0 is newer than 0.9.1), and a
    /// prerelease comes before its release (2.0.0-beta.9 before 2.0.0, after 1.x and 0.14.x),
    /// betas in the order of their numbers.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func split(_ version: String) -> (core: [Int], pre: [Substring]) {
            var text = Substring(version)
            if text.hasPrefix("v") { text = text.dropFirst() }
            if let plus = text.firstIndex(of: "+") { text = text[..<plus] }
            let parts = text.split(separator: "-", maxSplits: 1)
            let core = (parts.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
            let pre = parts.count > 1 ? parts[1].split(separator: ".") : []
            return (core, pre)
        }
        let x = split(a), y = split(b)
        for i in 0..<max(x.core.count, y.core.count) {
            let p = i < x.core.count ? x.core[i] : 0
            let q = i < y.core.count ? y.core[i] : 0
            if p != q { return p < q ? .orderedAscending : .orderedDescending }
        }
        // A release is newer than any of its prereleases.
        if x.pre.isEmpty != y.pre.isEmpty { return x.pre.isEmpty ? .orderedDescending : .orderedAscending }
        for i in 0..<max(x.pre.count, y.pre.count) {
            guard i < x.pre.count else { return .orderedAscending }
            guard i < y.pre.count else { return .orderedDescending }
            let p = x.pre[i], q = y.pre[i]
            if p == q { continue }
            switch (Int(p), Int(q)) {
            case let (m?, n?): return m < n ? .orderedAscending : .orderedDescending
            case (_?, nil): return .orderedAscending
            case (nil, _?): return .orderedDescending
            default: return p < q ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    /// Reads a `shasum -a 256` / `sha256sum` listing.
    static func expectedHash(in checksums: String, for file: String) -> String? {
        for line in checksums.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, let name = parts.last else { continue }
            if name.trimmingCharacters(in: CharacterSet(charactersIn: "*")) == file {
                return parts[0].lowercased()
            }
        }
        return nil
    }

    /// Hex SHA-256: CryptoKit on macOS, the built-in implementation elsewhere.
    static func sha256(_ data: Data) throws -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return SHA256Digest.hex(data)
        #endif
    }
}
