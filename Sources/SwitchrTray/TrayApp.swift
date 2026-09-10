#if os(Windows)
import Foundation
import WinSDK

// The Windows tray app: a notification-area icon, its menu, prompts and notifications. Everything
// it knows comes from running switchr.exe (installed next to it) with --json, the same contract
// the Linux tray uses.

private let wmNull: UINT = 0x0000
private let wmDestroy: UINT = 0x0002
private let wmClose: UINT = 0x0010
private let wmSettingChange: UINT = 0x001A
private let wmSetFont: UINT = 0x0030
private let wmContextMenu: UINT = 0x007B
private let wmCommand: UINT = 0x0111
private let wmTimer: UINT = 0x0113
private let wmTray: UINT = 0x8000 + 1
private let wmWorkDone: UINT = 0x8000 + 2
private let wmShowMenu: UINT = 0x8000 + 3
private let ninSelect: UINT = 0x0400
private let ninKeySelect: UINT = 0x0401
private let ninBalloonUserClick: UINT = 0x0405

private let refreshTimer: UINT_PTR = 1
private let updateTimer: UINT_PTR = 2
private let dialogTimer: UINT_PTR = 3

private func windowProc(_ hwnd: HWND?, _ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
    TrayApp.shared.handle(hwnd, message, wParam, lParam)
}

extension String {
    var wide: [WCHAR] { Array(utf16) + [0] }
}

private func copyWide<T>(_ string: String, into field: inout T) {
    withUnsafeMutableBytes(of: &field) { raw in
        let buffer = raw.bindMemory(to: WCHAR.self)
        guard buffer.count > 0 else { return }
        let units = Array(string.utf16.prefix(buffer.count - 1))
        for (index, unit) in units.enumerated() { buffer[index] = unit }
        buffer[units.count] = 0
    }
}

final class TrayApp {
    static let shared = TrayApp()

    private var window: HWND?
    private var icon: HICON?
    private var taskbarCreated: UINT = 0
    private var status: TrayStatus?
    private var update: TrayUpdate?
    private var busy: String?
    private var menuCommands: [UInt32: TrayCommand] = [:]
    private var balloonTarget: Foundation.UUID?
    private var pending: [() -> Void] = []
    private let lock = NSLock()

    private let folder: URL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    private var cli: String { folder.appendingPathComponent("switchr.exe").path }
    private var trayPath: String { folder.appendingPathComponent("switchr-tray.exe").path }
    private let arguments = CommandLine.arguments

    /// Scoop keeps apps under scoop\apps and updates them itself.
    private var updatedBy: String? {
        let path = folder.path.lowercased()
        return path.contains("\\scoop\\apps\\") || path.contains("/scoop/apps/") ? "Scoop" : nil
    }

    private var fixture: String? {
        arguments.firstIndex(of: "--status-file").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }

    private var settings: TraySettings {
        TraySettings(autoRefresh: Settings.bool("AutoRefresh", default: true),
                     autoInstallUpdates: Settings.bool("AutoInstallUpdates", default: true),
                     startsAtSignIn: StartAtSignIn.isOn,
                     canSelfUpdate: updatedBy == nil,
                     updatedBy: updatedBy)
    }

    func run() {
        let afterUpdate = arguments.contains("--after-update")
        var mutex = CreateMutexW(nil, false, "Local\\SwitchrTray".wide)
        if GetLastError() == DWORD(ERROR_ALREADY_EXISTS), fixture == nil {
            // After an update the old tray is still quitting; wait for it, otherwise one is enough.
            guard afterUpdate, let existing = mutex, WaitForSingleObject(existing, 10_000) != DWORD(WAIT_TIMEOUT) else { return }
            mutex = existing
        }
        _ = mutex

        _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT(bitPattern: -4))
        Self.followSystemMenuTheme()

        let instance = GetModuleHandleW(nil)
        let className = "SwitchrTrayWindow".wide
        className.withUnsafeBufferPointer { name in
            var windowClass = WNDCLASSEXW()
            windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            windowClass.lpfnWndProc = windowProc
            windowClass.hInstance = instance
            windowClass.lpszClassName = name.baseAddress
            RegisterClassExW(&windowClass)
        }
        window = CreateWindowExW(0, className, "Switchr".wide, 0, 0, 0, 0, 0, nil, nil, instance, nil)
        taskbarCreated = RegisterWindowMessageW("TaskbarCreated".wide)
        Prompt.register(instance: instance)

        if let fixture {
            status = (try? Data(contentsOf: URL(fileURLWithPath: fixture))).flatMap { try? TrayStatus.decode($0) }
            addIcon()
            if arguments.contains("--show-menu") { PostMessageW(window, wmShowMenu, 0, 0) }
            if arguments.contains("--show-dialog") { SetTimer(window, dialogTimer, 500, nil) }
        } else {
            addIcon()
            load(["status", "--json"]) { [weak self] in
                guard let self else { return }
                if self.settings.autoRefresh { self.refresh(claimAlerts: true) }
            }
            SetTimer(window, refreshTimer, 5 * 60 * 1000, nil)
            SetTimer(window, updateTimer, 12 * 60 * 60 * 1000, nil)
            checkForUpdates(announce: false)
        }

        var message = MSG()
        while GetMessageW(&message, nil, 0, 0) {
            if Prompt.handles(&message) { continue }
            TranslateMessage(&message)
            DispatchMessageW(&message)
        }
    }

    // MARK: Window messages

    func handle(_ hwnd: HWND?, _ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
        switch message {
        case wmTray:
            let event = UINT(UInt32(truncatingIfNeeded: lParam) & 0xFFFF)
            switch event {
            case wmContextMenu, ninSelect, ninKeySelect:
                showMenu()
            case ninBalloonUserClick:
                if let target = balloonTarget {
                    balloonTarget = nil
                    perform(.switchTo(target))
                }
            default:
                break
            }
            return 0
        case wmShowMenu:
            var area = RECT()
            SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, &area, 0)
            showMenu(at: POINT(x: area.right - 24, y: area.bottom - 8))
            return 0
        case wmCommand:
            let id = UInt32(truncatingIfNeeded: wParam) & 0xFFFF
            if let command = menuCommands[id] { perform(command) }
            return 0
        case wmTimer:
            if wParam == refreshTimer, settings.autoRefresh { refresh(claimAlerts: true) }
            if wParam == updateTimer { checkForUpdates(announce: false) }
            if wParam == dialogTimer {
                KillTimer(window, dialogTimer)
                if let account = status?.tools.flatMap(\.accounts).first { perform(.rename(account.id)) }
            }
            return 0
        case wmWorkDone:
            lock.lock()
            let work = pending
            pending.removeAll()
            lock.unlock()
            work.forEach { $0() }
            return 0
        case wmSettingChange:
            updateIcon()
            return 0
        case wmDestroy:
            removeIcon()
            PostQuitMessage(0)
            return 0
        default:
            if message == taskbarCreated, taskbarCreated != 0 {
                // Explorer restarted and forgot every tray icon.
                addIcon()
                return 0
            }
            return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }

    // MARK: Icon

    private func baseIconData() -> NOTIFYICONDATAW {
        var data = NOTIFYICONDATAW()
        data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        data.hWnd = window
        data.uID = 1
        return data
    }

    private func addIcon() {
        icon = makeIcon(values: TrayMenu.glyphValues(status))
        var data = baseIconData()
        data.uFlags = UINT(NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP)
        data.uCallbackMessage = wmTray
        data.hIcon = icon
        copyWide(TrayMenu.tooltip(status), into: &data.szTip)
        Shell_NotifyIconW(DWORD(NIM_ADD), &data)
        data.uVersion = UINT(NOTIFYICON_VERSION_4)
        Shell_NotifyIconW(DWORD(NIM_SETVERSION), &data)
    }

    private func updateIcon() {
        let previous = icon
        icon = makeIcon(values: TrayMenu.glyphValues(status))
        var data = baseIconData()
        data.uFlags = UINT(NIF_ICON | NIF_TIP | NIF_SHOWTIP)
        data.hIcon = icon
        copyWide(TrayMenu.tooltip(status), into: &data.szTip)
        Shell_NotifyIconW(DWORD(NIM_MODIFY), &data)
        if let previous { DestroyIcon(previous) }
    }

    private func removeIcon() {
        var data = baseIconData()
        Shell_NotifyIconW(DWORD(NIM_DELETE), &data)
    }

    private func notify(_ title: String, _ body: String, switchTo target: Foundation.UUID? = nil) {
        balloonTarget = target
        var data = baseIconData()
        data.uFlags = UINT(NIF_INFO)
        copyWide(title, into: &data.szInfoTitle)
        copyWide(body, into: &data.szInfo)
        data.dwInfoFlags = DWORD(NIIF_NONE) | 0x80 // NIIF_RESPECT_QUIET_TIME
        Shell_NotifyIconW(DWORD(NIM_MODIFY), &data)
    }

    private func makeIcon(values: [Double?]) -> HICON? {
        let size = Int(GetSystemMetricsForDpi(SM_CXSMICON, GetDpiForWindow(window)))
        let side = max(16, size)
        let pixels = TrayGlyph.pixels(size: side, values: values, darkTaskbar: !Self.taskbarIsLight)

        var header = BITMAPV5HEADER()
        header.bV5Size = DWORD(MemoryLayout<BITMAPV5HEADER>.size)
        header.bV5Width = LONG(side)
        header.bV5Height = -LONG(side)
        header.bV5Planes = 1
        header.bV5BitCount = 32
        header.bV5Compression = DWORD(BI_BITFIELDS)
        header.bV5RedMask = 0x00FF_0000
        header.bV5GreenMask = 0x0000_FF00
        header.bV5BlueMask = 0x0000_00FF
        header.bV5AlphaMask = 0xFF00_0000

        var bits: UnsafeMutableRawPointer?
        let screen = GetDC(nil)
        let color = withUnsafePointer(to: &header) { pointer in
            pointer.withMemoryRebound(to: BITMAPINFO.self, capacity: 1) {
                CreateDIBSection(screen, $0, UINT(DIB_RGB_COLORS), &bits, nil, 0)
            }
        }
        ReleaseDC(nil, screen)
        guard let color, let bits else { return nil }
        pixels.withUnsafeBytes { bits.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }

        let mask = CreateBitmap(Int32(side), Int32(side), 1, 1, nil)
        var info = ICONINFO(fIcon: true, xHotspot: 0, yHotspot: 0, hbmMask: mask, hbmColor: color)
        let icon = CreateIconIndirect(&info)
        DeleteObject(HGDIOBJ(color))
        if let mask { DeleteObject(HGDIOBJ(mask)) }
        return icon
    }

    // MARK: Menu

    private func showMenu(at anchor: POINT? = nil) {
        guard let menu = CreatePopupMenu() else { return }
        menuCommands.removeAll()
        var nextID: UInt32 = 100

        func append(_ items: [TrayMenuItem], to menu: HMENU) {
            for item in items {
                if item.isSeparator {
                    AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil)
                    continue
                }
                var flags = UINT(MF_STRING)
                if item.checked { flags |= UINT(MF_CHECKED) }
                if !item.enabled || item.isLabel { flags |= UINT(MF_GRAYED) }
                if !item.children.isEmpty, let submenu = CreatePopupMenu() {
                    append(item.children, to: submenu)
                    AppendMenuW(menu, flags | UINT(MF_POPUP), UINT_PTR(UInt(bitPattern: Int(bitPattern: submenu))), item.title.wide)
                    continue
                }
                var id: UInt32 = 0
                if let command = item.command {
                    id = nextID
                    nextID += 1
                    menuCommands[id] = command
                }
                AppendMenuW(menu, flags, UINT_PTR(id), item.title.wide)
            }
        }
        append(TrayMenu.build(status: status, busy: busy, update: update, settings: settings), to: menu)

        var point = POINT()
        if let anchor { point = anchor } else { GetCursorPos(&point) }
        SetForegroundWindow(window)
        TrackPopupMenuEx(menu, UINT(TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | TPM_RIGHTALIGN), point.x, point.y, window, nil)
        PostMessageW(window, wmNull, 0, 0)
        DestroyMenu(menu)
    }

    private func perform(_ command: TrayCommand) {
        if fixture != nil {
            // Saved data runs nothing; only the prompts open, for screenshots.
            switch command {
            case .rename, .remove, .budget: break
            case .quit: DestroyWindow(window); return
            default: return
            }
        }
        switch command {
        case .switchTo(let id):
            guard let (tool, account) = status?.account(id) else { return }
            busy = "Switching \(tool.name) to \(account.name)…"
            runCLI(["switch", id.uuidString, "--json"]) { [weak self] result in
                guard let self else { return }
                self.busy = nil
                if result.status == 0 {
                    if let action = try? TrayJSON.decoder.decode(TrayActionResult.self, from: result.stdout), let note = action.note {
                        self.notify(action.message, note)
                    }
                } else {
                    self.notify("Couldn't switch \(tool.name)", result.errorText)
                }
                self.load(["status", "--json"])
            }

        case .add(let toolID):
            guard let tool = status?.tools.first(where: { $0.id == toolID }) else { return }
            busy = "Waiting for a new \(tool.name) login…"
            notify("Sign in to \(tool.name) with the other account", "\(tool.signInHint) Switchr saves it as soon as it appears.")
            runCLI(["add", toolID, "--json"]) { [weak self] result in
                guard let self else { return }
                self.busy = nil
                if result.status == 0, let action = try? TrayJSON.decoder.decode(TrayActionResult.self, from: result.stdout) {
                    self.notify(tool.name, action.message)
                } else {
                    self.notify("No new \(tool.name) login saved", result.errorText)
                }
                self.load(["status", "--json"])
            }

        case .refresh:
            refresh(claimAlerts: false)

        case .insights:
            runCLI(["insights"]) { [weak self] result in
                if result.status != 0 { self?.notify("Couldn't open Insights", result.errorText) }
            }

        case .rename(let id):
            guard let (tool, account) = status?.account(id) else { return }
            guard let name = Prompt.ask(title: "Rename account",
                                        message: "A name for \(account.email) in \(tool.name). Leave it empty to show the email.",
                                        initial: account.label ?? "", action: "Save") else { return }
            guard fixture == nil else { return }
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            runCLI(trimmed.isEmpty ? ["rename", id.uuidString, "--clear"] : ["rename", id.uuidString, trimmed]) { [weak self] result in
                if result.status != 0 { self?.notify("Couldn't rename the account", result.errorText) }
                self?.load(["status", "--json"])
            }

        case .remove(let id):
            guard let (tool, account) = status?.account(id) else { return }
            let question = "Remove \(account.name) from \(tool.name)?\n\nSwitchr deletes its saved login. The account itself isn't affected, and you can add it again by signing in."
            guard MessageBoxW(window, question.wide, "Remove account".wide, UINT(MB_OKCANCEL | MB_ICONWARNING | MB_SETFOREGROUND | MB_TOPMOST)) == IDOK else { return }
            guard fixture == nil else { return }
            runCLI(["remove", id.uuidString]) { [weak self] result in
                if result.status != 0 { self?.notify("Couldn't remove the account", result.errorText) }
                self?.load(["status", "--json"])
            }

        case .budget:
            let current = status?.overallBudget
            var message = "A monthly budget for all accounts, in dollars at API prices. Switchr warns at 80% and 100%. Leave it empty for no budget."
            var answer = current.map { String(format: "%.0f", $0.amount) } ?? ""
            while true {
                guard let typed = Prompt.ask(title: "Budget", message: message, initial: answer, action: "Save") else { return }
                guard let amount = TrayMenu.budgetAmount(typed) else {
                    message = "Type an amount in dollars, like 200, or leave it empty for no budget."
                    answer = typed
                    continue
                }
                guard fixture == nil else { return }
                let arguments = amount.map { ["budget", "set", "all", String(format: "%.2f", $0), "--period", "month"] } ?? ["budget", "clear", "all"]
                runCLI(arguments) { [weak self] result in
                    if result.status != 0 { self?.notify("Couldn't change the budget", result.errorText) }
                    self?.load(["status", "--json"])
                }
                return
            }

        case .toggleAutoRefresh:
            Settings.set("AutoRefresh", !settings.autoRefresh)

        case .toggleAutoInstall:
            Settings.set("AutoInstallUpdates", !settings.autoInstallUpdates)
            if settings.autoInstallUpdates { installUpdateIfIdle() }

        case .toggleStartAtSignIn:
            StartAtSignIn.set(!StartAtSignIn.isOn, command: "\"\(trayPath)\"")

        case .checkForUpdates:
            checkForUpdates(announce: true)

        case .installUpdate:
            installUpdate()

        case .quit:
            DestroyWindow(window)
        }
    }

    // MARK: Data

    private func refresh(claimAlerts: Bool) {
        var arguments = ["refresh", "--json"]
        if claimAlerts { arguments.append("--claim-alerts") }
        if busy == nil { busy = "Reading limits…" }
        load(arguments) { [weak self] in
            guard let self else { return }
            if self.busy == "Reading limits…" { self.busy = nil }
            for alert in self.status?.alerts ?? [] {
                self.notify(alert.title, alert.body, switchTo: alert.switchTo)
            }
        }
    }

    private func load(_ arguments: [String], then: (() -> Void)? = nil) {
        runCLI(arguments) { [weak self] result in
            guard let self else { return }
            if result.status == 0, let status = try? TrayStatus.decode(result.stdout) {
                self.status = status
                self.updateIcon()
            } else if result.status != 0, self.status == nil {
                self.notify("Switchr couldn't read your accounts", result.errorText)
            }
            then?()
        }
    }

    private func checkForUpdates(announce: Bool) {
        runCLI(["update", "--check", "--json"]) { [weak self] result in
            guard let self else { return }
            guard result.status == 0, let update = try? TrayJSON.decoder.decode(TrayUpdate.self, from: result.stdout) else {
                if announce { self.notify("Couldn't check for updates", result.errorText) }
                return
            }
            self.update = update
            let settings = self.settings
            if update.available, settings.canSelfUpdate, settings.autoInstallUpdates {
                self.installUpdateIfIdle()
                return
            }
            if update.available, announce || Settings.string("NotifiedVersion") != update.latest {
                Settings.set("NotifiedVersion", update.latest)
                let how = settings.canSelfUpdate ? "Choose Update in the menu." : "Update it with: scoop update switchr"
                self.notify("Switchr \(update.latest) is available", how)
            } else if announce {
                self.notify("Switchr", "Switchr \(update.current) is the latest version.")
            }
        }
    }

    /// Installs a found release unless something is in progress, as the Mac app does.
    private func installUpdateIfIdle() {
        guard let update, update.available, busy == nil else { return }
        installUpdate()
    }

    private func installUpdate() {
        guard let update, settings.canSelfUpdate else { return }
        busy = "Installing Switchr \(update.latest)…"
        runCLI(["update", "--json"]) { [weak self] result in
            guard let self else { return }
            self.busy = nil
            guard result.status == 0 else {
                self.notify("Switchr didn't update", result.errorText)
                return
            }
            Self.launch(self.trayPath, ["--after-update"])
            DestroyWindow(self.window)
        }
    }

    // MARK: Running switchr.exe

    struct CLIResult {
        let status: UInt32
        let stdout: Data
        let stderr: Data

        var errorText: String {
            let text = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = text.hasPrefix("switchr: ") ? String(text.dropFirst(9)) : text
            return cleaned.isEmpty ? "switchr.exe exited with code \(status)." : String(cleaned.prefix(250))
        }
    }

    /// Runs switchr.exe on a background thread without a console window, then calls back on the
    /// window thread.
    private func runCLI(_ arguments: [String], completion: @escaping (CLIResult) -> Void) {
        guard fixture == nil else { return }
        let executable = cli
        let target = window
        DispatchQueue.global().async { [weak self] in
            let result = Self.execute(executable, arguments)
            guard let self else { return }
            self.lock.lock()
            self.pending.append { completion(result) }
            self.lock.unlock()
            PostMessageW(target, wmWorkDone, 0, 0)
        }
    }

    private static func execute(_ executable: String, _ arguments: [String]) -> CLIResult {
        var security = SECURITY_ATTRIBUTES(nLength: DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size), lpSecurityDescriptor: nil, bInheritHandle: true)
        var outRead: HANDLE?, outWrite: HANDLE?, errRead: HANDLE?, errWrite: HANDLE?
        guard CreatePipe(&outRead, &outWrite, &security, 0), CreatePipe(&errRead, &errWrite, &security, 0) else {
            return CLIResult(status: 1, stdout: Data(), stderr: Data("Couldn't start switchr.exe.".utf8))
        }
        SetHandleInformation(outRead, DWORD(HANDLE_FLAG_INHERIT), 0)
        SetHandleInformation(errRead, DWORD(HANDLE_FLAG_INHERIT), 0)
        let nul = CreateFileW("NUL".wide, DWORD(0x8000_0000), DWORD(FILE_SHARE_READ), &security, DWORD(OPEN_EXISTING), 0, nil)

        var startup = STARTUPINFOW()
        startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
        startup.dwFlags = DWORD(STARTF_USESTDHANDLES)
        startup.hStdInput = nul
        startup.hStdOutput = outWrite
        startup.hStdError = errWrite

        var process = PROCESS_INFORMATION()
        var commandLine = ([executable] + arguments).map(quote).joined(separator: " ").wide
        let started = CreateProcessW(nil, &commandLine, nil, nil, true, DWORD(CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT), nil, nil, &startup, &process)
        CloseHandle(outWrite)
        CloseHandle(errWrite)
        CloseHandle(nul)
        guard started else {
            CloseHandle(outRead)
            CloseHandle(errRead)
            return CLIResult(status: 1, stdout: Data(), stderr: Data("Couldn't find switchr.exe next to switchr-tray.exe.".utf8))
        }

        final class Box: @unchecked Sendable { var data = Data() }
        let errors = Box()
        let drained = DispatchSemaphore(value: 0)
        let errHandle = errRead
        DispatchQueue.global().async {
            errors.data = readAll(errHandle)
            drained.signal()
        }
        let output = readAll(outRead)
        drained.wait()
        WaitForSingleObject(process.hProcess, 0xFFFF_FFFF)
        var code: DWORD = 1
        GetExitCodeProcess(process.hProcess, &code)
        CloseHandle(process.hProcess)
        CloseHandle(process.hThread)
        CloseHandle(outRead)
        CloseHandle(errRead)
        return CLIResult(status: code, stdout: output, stderr: errors.data)
    }

    private static func readAll(_ handle: HANDLE?) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            var read: DWORD = 0
            let ok = buffer.withUnsafeMutableBytes { ReadFile(handle, $0.baseAddress, DWORD($0.count), &read, nil) }
            if !ok || read == 0 { break }
            data.append(contentsOf: buffer[0..<Int(read)])
        }
        return data
    }

    /// Quotes one argument the way the Microsoft C runtime splits command lines.
    static func quote(_ argument: String) -> String {
        guard argument.isEmpty || argument.contains(where: { " \t\"".contains($0) }) else { return argument }
        var result = "\""
        var backslashes = 0
        for character in argument {
            if character == "\\" {
                backslashes += 1
            } else if character == "\"" {
                result += String(repeating: "\\", count: backslashes * 2 + 1) + "\""
                backslashes = 0
            } else {
                result += String(repeating: "\\", count: backslashes) + String(character)
                backslashes = 0
            }
        }
        return result + String(repeating: "\\", count: backslashes * 2) + "\""
    }

    private static func launch(_ executable: String, _ arguments: [String]) {
        var startup = STARTUPINFOW()
        startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
        var process = PROCESS_INFORMATION()
        var commandLine = ([executable] + arguments).map(quote).joined(separator: " ").wide
        if CreateProcessW(nil, &commandLine, nil, nil, false, DWORD(DETACHED_PROCESS), nil, nil, &startup, &process) {
            CloseHandle(process.hProcess)
            CloseHandle(process.hThread)
        }
    }

    // MARK: System appearance

    private static let personalizeKey = "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"

    /// The taskbar follows the system theme (not the apps theme).
    static var taskbarIsLight: Bool {
        var value: DWORD = 0
        var size = DWORD(MemoryLayout<DWORD>.size)
        let result = RegGetValueW(Registry.currentUser, personalizeKey.wide, "SystemUsesLightTheme".wide, DWORD(RRF_RT_REG_DWORD), nil, &value, &size)
        return result == 0 && value == 1
    }

    /// Lets the menu go dark with the system, as Explorer's own menus do.
    private static func followSystemMenuTheme() {
        guard let uxtheme = LoadLibraryW("uxtheme.dll".wide),
              let setPreferredAppMode = GetProcAddress(uxtheme, UnsafePointer<CHAR>(bitPattern: 135)),
              let flushMenuThemes = GetProcAddress(uxtheme, UnsafePointer<CHAR>(bitPattern: 136)) else { return }
        typealias SetMode = @convention(c) (Int32) -> Int32
        typealias Flush = @convention(c) () -> Void
        _ = unsafeBitCast(setPreferredAppMode, to: SetMode.self)(1) // AllowDark
        unsafeBitCast(flushMenuThemes, to: Flush.self)()
    }
}

// MARK: Prompt

/// A small text prompt in the system's message font: a question, a text field, Save and Cancel.
/// Enter saves and Escape cancels, as in any Windows dialog.
enum Prompt {
    private static let className = "SwitchrPrompt".wide
    private static var instance: HINSTANCE?
    private static var dialog: HWND?
    private static var edit: HWND?
    private static var result: String?
    private static var finished = false
    private static var font: HFONT?

    private static let idSave: Int32 = 1
    private static let idCancel: Int32 = 2

    static func register(instance: HINSTANCE?) {
        self.instance = instance
        className.withUnsafeBufferPointer { name in
            var windowClass = WNDCLASSEXW()
            windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            windowClass.lpfnWndProc = promptProc
            windowClass.hInstance = instance
            windowClass.hbrBackground = GetSysColorBrush(COLOR_WINDOW)
            windowClass.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
            windowClass.lpszClassName = name.baseAddress
            RegisterClassExW(&windowClass)
        }
    }

    /// Lets Tab, Enter and Escape work inside the prompt.
    static func handles(_ message: inout MSG) -> Bool {
        guard let dialog else { return false }
        return IsDialogMessageW(dialog, &message)
    }

    static func ask(title: String, message: String, initial: String, action: String) -> String? {
        guard dialog == nil else { return nil }
        let dpi = Double(GetDpiForSystem())
        func scaled(_ value: Double) -> Int32 { Int32((value * dpi / 96).rounded()) }

        var metrics = NONCLIENTMETRICSW()
        metrics.cbSize = UINT(MemoryLayout<NONCLIENTMETRICSW>.size)
        SystemParametersInfoForDpi(UINT(SPI_GETNONCLIENTMETRICS), metrics.cbSize, &metrics, 0, UINT(dpi))
        font = CreateFontIndirectW(&metrics.lfMessageFont)

        let width = scaled(440), height = scaled(200)
        var area = RECT()
        SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, &area, 0)
        let x = area.left + (area.right - area.left - width) / 2
        let y = area.top + (area.bottom - area.top - height) / 2

        let style = DWORD(WS_CAPTION | WS_SYSMENU) | DWORD(WS_POPUP)
        dialog = CreateWindowExW(DWORD(WS_EX_DLGMODALFRAME | WS_EX_TOPMOST), className, title.wide, style, x, y, width, height, nil, nil, instance, nil)
        guard let dialog else { return nil }

        var client = RECT()
        GetClientRect(dialog, &client)
        let margin = scaled(16), inner = client.right - margin * 2
        let child = DWORD(WS_CHILD | WS_VISIBLE)

        let label = CreateWindowExW(0, "STATIC".wide, message.wide, child, margin, margin, inner, scaled(52), dialog, nil, instance, nil)
        edit = CreateWindowExW(DWORD(WS_EX_CLIENTEDGE), "EDIT".wide, initial.wide, child | DWORD(WS_TABSTOP) | DWORD(ES_AUTOHSCROLL),
                               margin, margin + scaled(60), inner, scaled(26), dialog, nil, instance, nil)
        let buttonWidth = scaled(92), buttonHeight = scaled(30), buttonTop = client.bottom - margin - buttonHeight
        let cancel = CreateWindowExW(0, "BUTTON".wide, "Cancel".wide, child | DWORD(WS_TABSTOP) | DWORD(BS_PUSHBUTTON),
                                     client.right - margin - buttonWidth, buttonTop, buttonWidth, buttonHeight, dialog, HMENU(bitPattern: Int(idCancel)), instance, nil)
        let save = CreateWindowExW(0, "BUTTON".wide, action.wide, child | DWORD(WS_TABSTOP) | DWORD(BS_DEFPUSHBUTTON),
                                   client.right - margin * 3 / 2 - buttonWidth * 2, buttonTop, buttonWidth, buttonHeight, dialog, HMENU(bitPattern: Int(idSave)), instance, nil)
        for control in [label, edit, cancel, save] {
            SendMessageW(control, wmSetFont, WPARAM(UInt(bitPattern: Int(bitPattern: font))), 1)
        }
        SendMessageW(edit, UINT(EM_SETSEL), 0, -1)

        result = nil
        finished = false
        ShowWindow(dialog, SW_SHOW)
        SetForegroundWindow(dialog)
        SetFocus(edit)

        var msg = MSG()
        while !finished, GetMessageW(&msg, nil, 0, 0) {
            if IsDialogMessageW(dialog, &msg) { continue }
            TranslateMessage(&msg)
            DispatchMessageW(&msg)
        }
        DestroyWindow(dialog)
        self.dialog = nil
        edit = nil
        if let font { DeleteObject(HGDIOBJ(font)) }
        font = nil
        return result
    }

    fileprivate static func handle(_ hwnd: HWND?, _ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
        switch message {
        case wmCommand:
            let id = Int32(truncatingIfNeeded: wParam & 0xFFFF)
            if id == idSave {
                let length = GetWindowTextLengthW(edit)
                var buffer = [WCHAR](repeating: 0, count: Int(length) + 1)
                GetWindowTextW(edit, &buffer, length + 1)
                result = String(decoding: buffer.prefix(Int(length)), as: UTF16.self)
                finished = true
            } else if id == idCancel {
                finished = true
            }
            return 0
        case wmClose:
            finished = true
            return 0
        default:
            return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }
}

private func promptProc(_ hwnd: HWND?, _ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
    Prompt.handle(hwnd, message, wParam, lParam)
}

// MARK: Registry

enum Registry {
    /// HKEY_CURRENT_USER, which C defines as a sign-extended constant pointer.
    static let currentUser = HKEY(bitPattern: Int(Int32(bitPattern: 0x8000_0001)))
}

/// The tray's settings, in HKCU\Software\Switchr. `switchr reset` removes them.
enum Settings {
    private static let key = "Software\\Switchr"

    static func bool(_ name: String, default fallback: Bool) -> Bool {
        var value: DWORD = 0
        var size = DWORD(MemoryLayout<DWORD>.size)
        guard RegGetValueW(Registry.currentUser, key.wide, name.wide, DWORD(RRF_RT_REG_DWORD), nil, &value, &size) == 0 else { return fallback }
        return value != 0
    }

    static func set(_ name: String, _ on: Bool) {
        var value: DWORD = on ? 1 : 0
        _ = RegSetKeyValueW(Registry.currentUser, key.wide, name.wide, DWORD(REG_DWORD), &value, DWORD(MemoryLayout<DWORD>.size))
    }

    static func string(_ name: String) -> String? {
        var size: DWORD = 0
        guard RegGetValueW(Registry.currentUser, key.wide, name.wide, DWORD(RRF_RT_REG_SZ), nil, nil, &size) == 0, size > 0 else { return nil }
        var buffer = [WCHAR](repeating: 0, count: Int(size) / 2 + 1)
        guard RegGetValueW(Registry.currentUser, key.wide, name.wide, DWORD(RRF_RT_REG_SZ), nil, &buffer, &size) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)
    }

    static func set(_ name: String, _ text: String) {
        let value = text.wide
        value.withUnsafeBytes { bytes in
            _ = RegSetKeyValueW(Registry.currentUser, key.wide, name.wide, DWORD(REG_SZ), bytes.baseAddress, DWORD(bytes.count))
        }
    }
}

/// The per-user Run key, the same switch Task Manager's Startup apps page flips.
enum StartAtSignIn {
    private static let key = "Software\\Microsoft\\Windows\\CurrentVersion\\Run"
    private static let name = "Switchr"

    static var isOn: Bool {
        RegGetValueW(Registry.currentUser, key.wide, name.wide, DWORD(RRF_RT_REG_SZ), nil, nil, nil) == 0
    }

    static func set(_ on: Bool, command: String) {
        if on {
            let value = command.wide
            value.withUnsafeBytes { bytes in
                _ = RegSetKeyValueW(Registry.currentUser, key.wide, name.wide, DWORD(REG_SZ), bytes.baseAddress, DWORD(bytes.count))
            }
        } else {
            _ = RegDeleteKeyValueW(Registry.currentUser, key.wide, name.wide)
        }
    }
}
#endif
