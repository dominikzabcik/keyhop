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
}

/// Reading this repository's GitHub releases, shared by the macOS updater and `keyhop update`.
enum Releases {
    static let repository = "dominikzabcik/keyhop"

    static func latest() async throws -> ReleaseInfo {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("keyhop/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        let (data, status) = try await HTTP.send(request)
        guard status == 200, let body = JSON.object(data),
              let tag = body["tag_name"] as? String,
              let page = (body["html_url"] as? String).flatMap(URL.init(string:)) else {
            throw KeyhopError("GitHub didn't return a release.")
        }
        var assets: [String: URL] = [:]
        for asset in body["assets"] as? [[String: Any]] ?? [] {
            if let name = asset["name"] as? String, let url = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)) {
                assets[name] = url
            }
        }
        return ReleaseInfo(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, page: page, assets: assets)
    }

    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 180)
        request.setValue("keyhop/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        let (data, status) = try await HTTP.send(request)
        guard status == 200 else { throw KeyhopError("The download failed (HTTP \(status)).") }
        return data
    }

    /// Compares dotted versions numerically, so 0.10.0 is newer than 0.9.1.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
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
