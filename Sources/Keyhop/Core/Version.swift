import Foundation

enum AppVersion {
    /// Kept in step with the VERSION file; the release workflow refuses a mismatch.
    static let number = "0.14.5"

    static var current: String {
        #if os(macOS)
        // A beta's full version (2.0.0-beta.4) is KeyhopVersion; CFBundleShortVersionString can only
        // hold the numbers, so it is the fallback for builds from before channels.
        if let full = Bundle.main.infoDictionary?["KeyhopVersion"] as? String, !full.isEmpty { return full }
        if let bundled = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { return bundled }
        #endif
        return number
    }

    /// True for a beta or any other prerelease build.
    static var isPrerelease: Bool { current.contains("-") }
}
