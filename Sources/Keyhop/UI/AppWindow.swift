#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import WebKit

/// Keyhop's window on the Mac: the dashboard, served by the app itself on 127.0.0.1 and shown in a
/// native window. While it's open Keyhop has a Dock icon and a menu bar; once it closes, the app
/// goes back to living in the menu bar.
@MainActor
enum AppWindow {
    static let urlScheme = "keyhop"
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
            AccountStore.shared.notice = "Couldn't open Keyhop's window: \(error.localizedDescription)"
        }
    }

    /// The section in `keyhop://open?section=usage`.
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
            return DashboardAction(message: "Keyhop \(Updater.currentVersion) is the latest version.", note: nil)
        }
        Task { await updater.install() }
        return DashboardAction(message: "Installing Keyhop \(release.version).", note: "Keyhop reopens in a moment.")
    }
}

/// The dashboard's server inside the app, started the first time the window opens and kept while
/// Keyhop runs. The live one shares the menu's AccountService, so a change made in the window and
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
    private static let frameName = "KeyhopWindow"
    private static let messageName = "keyhopWindow"

    let window: NSWindow
    /// Let go of when the window closes: a loaded page costs its own process, hundreds of megabytes
    /// after a long day, and AppKit can keep a closed window (and everything in it) for a while.
    private var webView: WKWebView?
    private let host: DashboardHost

    init(host: DashboardHost, section: String) {
        self.host = host
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
        let webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        self.webView = webView
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()

        webView.configuration.userContentController.add(ScriptBridge(self), name: Self.messageName)
        // The web view is clear, so the page's tinted surfaces sit on the blur below, and no white
        // flashes through on loads and resizes.
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = self
        webView.uiDelegate = self

        window.title = "Keyhop"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // An empty unified toolbar makes the title bar as tall as the page's top row, so the window
        // buttons sit centered in it.
        let toolbar = NSToolbar(identifier: "KeyhopWindow")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false
        // Fully clear with a shadow leaves a notch at the rounded corners; a trace of alpha keeps them clean.
        window.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        window.hasShadow = true
        window.minSize = NSSize(width: 960, height: 620)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        // The whole app is glass: the page tints itself over the desktop, blurred behind the window.
        if DesktopBlur.isAvailable {
            window.contentView = webView
        } else {
            let vibrancy = NSVisualEffectView(frame: frame)
            vibrancy.material = .underWindowBackground
            vibrancy.blendingMode = .behindWindow
            vibrancy.state = .active
            webView.frame = vibrancy.bounds
            webView.autoresizingMask = [.width, .height]
            vibrancy.addSubview(webView)
            window.contentView = vibrancy
        }
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
        // The saved blur, until the page reports its own.
        let appearance = DashboardAppearance.load()
        DesktopBlur.set(window, radius: appearance.glass < 1 ? appearance.blur : 0)
        window.invalidateShadow()
    }

    func go(to section: String) {
        guard let webView else { return }
        if webView.isLoading {
            webView.load(URLRequest(url: host.url(section: section)))
        } else {
            webView.evaluateJavaScript("location.hash = \"\(section)\"")
        }
    }

    // MARK: Window

    func windowWillClose(_ notification: Notification) {
        // Closing the window lets go of the page: no delegates, no view, no reference here. AppKit
        // keeps caches of its own that outlive this, so the web content process can still sit on
        // its memory for a while, but nothing here asks it to stay.
        let retired = webView
        webView = nil
        window.makeFirstResponder(nil)
        window.contentView = nil
        if let retired {
            retired.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageName)
            retired.stopLoading()
            retired.navigationDelegate = nil
            retired.uiDelegate = nil
            retired.removeFromSuperview()
        }
        AppWindow.closed()
    }

    /// The page's top row stands in for a title bar: it asks to move or zoom the window. Appearance
    /// sends "blur:24" as its Blur setting changes.
    func received(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.host == "127.0.0.1" else { return }
        if let body = message.body as? String, body.hasPrefix("blur:"), let radius = Int(body.dropFirst(5)) {
            DesktopBlur.set(window, radius: radius)
            return
        }
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
        // Only worth reloading while the window is still showing it.
        guard self.webView != nil else { return }
        webView.reload()
    }

    /// Links out of Keyhop, like a release page, open in the browser.
    private static func openOutside(_ url: URL) {
        guard url.scheme == "https" || url.scheme == "http" else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Blurs whatever is behind a window, the way terminals blur their backgrounds. It's a private
/// WindowServer call, looked up at run time; if a macOS release drops it, the window uses the standard
/// vibrancy view instead.
enum DesktopBlur {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SetRadius = @convention(c) (Int32, UInt32, Int32) -> Int32

    private static let functions: (connection: MainConnection, setRadius: SetRadius)? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let connection = dlsym(handle, "CGSMainConnectionID"),
              let setRadius = dlsym(handle, "CGSSetWindowBackgroundBlurRadius") else { return nil }
        return (unsafeBitCast(connection, to: MainConnection.self), unsafeBitCast(setRadius, to: SetRadius.self))
    }()

    static var isAvailable: Bool { functions != nil }

    static func set(_ window: NSWindow, radius: Int) {
        guard let functions, window.windowNumber > 0 else { return }
        _ = functions.setRadius(functions.connection(), UInt32(window.windowNumber), Int32(min(64, max(0, radius))))
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
