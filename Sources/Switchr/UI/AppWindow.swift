#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import WebKit

/// Switchr's window on the Mac: the dashboard, served by the app itself on 127.0.0.1 and shown in a
/// native window. While it's open Switchr has a Dock icon and a menu bar; once it closes, the app
/// goes back to living in the menu bar.
@MainActor
enum AppWindow {
    static let urlScheme = "switchr"
    /// Set by `--preview-window` to show sample data.
    static var sample = false
    private static var controller: AppWindowController?

    static var isOpen: Bool { controller != nil }

    static func show(section: String? = nil) {
        let wanted = section.flatMap { Dashboard.sections.contains($0) ? $0 : nil }
        if let controller {
            if let wanted { controller.go(to: wanted) }
            controller.present()
            return
        }
        do {
            let host = try DashboardHost.shared(sample: sample)
            let controller = AppWindowController(host: host, section: wanted ?? "overview")
            self.controller = controller
            controller.present()
        } catch {
            AccountStore.shared.notice = "Couldn't open Switchr's window: \(error.localizedDescription)"
        }
    }

    /// The section in `switchr://open?section=usage`.
    static func section(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "section" }?.value
    }

    fileprivate static func closed() {
        controller = nil
        NSApp.setActivationPolicy(.accessory)
    }

    /// Install from the window's Settings, the Mac app's way: verified, swapped in place, relaunched.
    static func installUpdate() async -> DashboardAction {
        let updater = Updater.shared
        await updater.check(userInitiated: false, allowAutoInstall: false)
        guard let release = updater.available else {
            return DashboardAction(message: "Switchr \(Updater.currentVersion) is the latest version.", note: nil)
        }
        Task { await updater.install() }
        return DashboardAction(message: "Installing Switchr \(release.version).", note: "Switchr reopens in a moment.")
    }
}

/// The dashboard's server inside the app, started the first time the window opens and kept while
/// Switchr runs. The live one shares the menu's AccountService, so a change made in the window and
/// one made in the menu never overwrite each other.
@MainActor
final class DashboardHost {
    let port: UInt16
    let token = Dashboard.randomToken()
    private let server: LoopbackServer

    private static var live: DashboardHost?
    private static var sample: DashboardHost?

    static func shared(sample isSample: Bool) throws -> DashboardHost {
        if let existing = isSample ? sample : live { return existing }
        let host = try DashboardHost(session: isSample ? DashboardSession(sample: true) : makeSession())
        if isSample { sample = host } else { live = host }
        return host
    }

    private init(session: DashboardSession) throws {
        server = try LoopbackServer()
        port = server.port
        let token = token, port = port
        server.start { request in await session.respond(to: request, token: token, port: port) }
    }

    private static func makeSession() throws -> DashboardSession {
        guard let service = AccountStore.shared.accountService else { return try DashboardSession(sample: false) }
        let tracker = try TrackerEngine(url: Platform.dataDirectory.appendingPathComponent("usage.sqlite"))
        return try DashboardSession(
            sample: false,
            workspace: { Workspace(service: service, tracker: tracker, state: CLIState.load()) },
            changed: { Task { @MainActor in AccountStore.shared.adoptChanges() } },
            installUpdate: { await AppWindow.installUpdate() }
        )
    }

    func url(section: String) -> URL {
        URL(string: Dashboard.address(port: port, token: token, section: section) + "&w=mac")!
    }
}

@MainActor
private final class AppWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private static let frameName = "SwitchrWindow"
    private static let messageName = "switchrWindow"

    let window: NSWindow
    private let webView: WKWebView
    private let host: DashboardHost

    init(host: DashboardHost, section: String) {
        self.host = host
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
        webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()

        webView.configuration.userContentController.add(ScriptBridge(self), name: Self.messageName)
        // The page paints its own near-black; this keeps a white flash out of loads and resizes.
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = Brand.backgroundColor
        webView.navigationDelegate = self
        webView.uiDelegate = self

        window.title = "Switchr"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // An empty unified toolbar makes the title bar as tall as the page's top row, so the window
        // buttons sit centered in it.
        let toolbar = NSToolbar(identifier: "SwitchrWindow")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Brand.backgroundColor
        window.minSize = NSSize(width: 960, height: 620)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentView = webView
        window.delegate = self
        let restored = window.setFrameUsingName(Self.frameName)
        window.setFrameAutosaveName(Self.frameName)
        if !restored { window.center() }

        webView.load(URLRequest(url: host.url(section: section)))
    }

    func present() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func go(to section: String) {
        if webView.isLoading {
            webView.load(URLRequest(url: host.url(section: section)))
        } else {
            webView.evaluateJavaScript("location.hash = \"\(section)\"")
        }
    }

    // MARK: Window

    func windowWillClose(_ notification: Notification) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageName)
        AppWindow.closed()
    }

    /// The page's top row stands in for a title bar: it asks to move or zoom the window.
    func received(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.host == "127.0.0.1" else { return }
        switch message.body as? String {
        case "drag":
            let current = NSApp.currentEvent.flatMap { $0.type == .leftMouseDown || $0.type == .leftMouseDragged ? $0 : nil }
            let event = current ?? NSEvent.mouseEvent(with: .leftMouseDown, location: window.mouseLocationOutsideOfEventStream,
                                                      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                      clickCount: 1, pressure: 1)
            if let event { window.performDrag(with: event) }
        case "zoom":
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window.performMiniaturize(nil)
            case "None": break
            default: window.performZoom(nil)
            }
        default:
            break
        }
    }

    // MARK: Web view

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if url.host == "127.0.0.1", url.port == Int(host.port) { return .allow }
        Self.openOutside(url)
        return .cancel
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { Self.openOutside(url) }
        return nil
    }

    /// A file input on the page, like Appearance's picture, opens the system's open panel.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.allowedContentTypes = [.image]
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    /// Links out of Switchr, like a release page, open in the browser.
    private static func openOutside(_ url: URL) {
        guard url.scheme == "https" || url.scheme == "http" else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Holds the window weakly, so the web view's handler list doesn't keep it alive.
@MainActor
private final class ScriptBridge: NSObject, WKScriptMessageHandler {
    weak var target: AppWindowController?

    init(_ target: AppWindowController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.received(message)
    }
}
#endif
