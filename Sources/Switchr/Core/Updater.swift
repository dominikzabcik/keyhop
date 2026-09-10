#if os(macOS)
import AppKit
import SwiftUI

/// Checks GitHub for a newer release and installs it in place: download, verify the SHA-256
/// against the release's checksum file, swap the app bundle, relaunch.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release: Equatable {
        let version: String
        let archive: URL
        let checksums: URL?
        let page: URL
    }

    enum Phase: Equatable {
        case idle, checking, downloading, installing
        case failed(String)
    }

    @Published private(set) var available: Release?
    @Published private(set) var phase: Phase = .idle

    nonisolated static var currentVersion: String { AppVersion.current }

    /// At most once a day, when automatic checks are on and Switchr runs as an app.
    func checkIfDue() {
        guard UserDefaults.standard.bool(forKey: "checkForUpdates"), Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86400 else { return }
        Task { await check(userInitiated: false) }
    }

    /// `allowAutoInstall: false` only looks, even when automatic installs are on.
    func check(userInitiated: Bool, allowAutoInstall: Bool = true) async {
        switch phase {
        case .checking, .downloading, .installing: return
        default: break
        }
        phase = .checking
        UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
        do {
            let info = try await Releases.latest()
            if Releases.isNewer(info.version, than: Self.currentVersion) {
                guard let archive = info.assets["Switchr.zip"] else { throw SwitchrError("The latest release has no Switchr.zip.") }
                available = Release(version: info.version, archive: archive, checksums: info.assets["SHA256SUMS"], page: info.page)
            } else {
                available = nil
            }
            phase = .idle
            if userInitiated, available == nil {
                AccountStore.shared.notice = "Switchr \(Self.currentVersion) is the latest version."
            }
            if allowAutoInstall, !userInitiated, available != nil, UserDefaults.standard.bool(forKey: "autoInstallUpdates") {
                await installWhenIdle()
            }
        } catch {
            phase = userInitiated ? .failed("Couldn't check for updates: \(error.localizedDescription)") : .idle
        }
    }

    /// Waits until no switch or sign-in is in progress, so an automatic update never interrupts one.
    private func installWhenIdle() async {
        for _ in 0..<120 {
            let store = AccountStore.shared
            if store.switching == nil, store.addingFor == nil {
                await install()
                return
            }
            try? await Task.sleep(for: .seconds(30))
        }
    }

    /// Returns true once the new version is in place.
    @discardableResult
    func install(relaunch: Bool = true) async -> Bool {
        guard let release = available else { return false }
        let bundle = URL(fileURLWithPath: Bundle.main.bundlePath)
        guard bundle.pathExtension == "app" else {
            phase = .failed("Updates only work for the installed app.")
            return false
        }
        guard let checksums = release.checksums else {
            phase = .failed("This release has no checksum file, so Switchr won't install it.")
            return false
        }

        phase = .downloading
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("switchr-update-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let archive = try await Releases.download(release.archive)
            let sums = try await Releases.download(checksums)
            guard Releases.expectedHash(in: String(decoding: sums, as: UTF8.self), for: "Switchr.zip") == (try Releases.sha256(archive)) else {
                throw SwitchrError("The download didn't match the release checksum.")
            }

            phase = .installing
            let zip = work.appendingPathComponent("Switchr.zip")
            try archive.write(to: zip)
            let unpacked = work.appendingPathComponent("unpacked")
            let result = try Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
            let fresh = unpacked.appendingPathComponent("Switchr.app")
            guard result.status == 0,
                  let info = NSDictionary(contentsOf: fresh.appendingPathComponent("Contents/Info.plist")),
                  info["CFBundleShortVersionString"] as? String == release.version else {
                throw SwitchrError("The downloaded app isn't Switchr \(release.version).")
            }
            _ = try? Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", fresh.path])
            _ = try FileManager.default.replaceItemAt(bundle, withItemAt: fresh)

            available = nil
            phase = .idle
            if relaunch { Self.relaunch(bundle) }
            return true
        } catch {
            phase = .failed(error.localizedDescription)
            return false
        }
    }

    private static func relaunch(_ bundle: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", bundle.path]
        try? process.run()
        NSApp.terminate(nil)
    }
}

/// Shown in the menu when a newer release is out, or when an update failed.
struct UpdateLine: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        if let release = updater.available {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Switchr \(release.version) is out")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Brand.bone)
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                switch updater.phase {
                case .downloading, .installing:
                    ProgressView().controlSize(.small)
                default:
                    QuietButton("Notes") { NSWorkspace.shared.open(release.page) }
                    Button("Update") { Task { await updater.install() } }
                        .buttonStyle(BoneButtonStyle(compact: true))
                        .frame(width: 76)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        } else if case .failed(let message) = updater.phase {
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }

    private var caption: String {
        switch updater.phase {
        case .downloading: "Downloading and checking the release…"
        case .installing: "Installing. Switchr reopens in a moment."
        case .failed(let message): message
        default: "You have \(Updater.currentVersion). Updates are verified before they install."
        }
    }
}
#endif
