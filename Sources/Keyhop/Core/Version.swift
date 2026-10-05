import Foundation

enum AppVersion {
    /// Kept in step with the VERSION file; the release workflow refuses a mismatch.
    static let number = "0.14.4"

    static var current: String {
        #if os(macOS)
        if let bundled = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { return bundled }
        #endif
        return number
    }
}
