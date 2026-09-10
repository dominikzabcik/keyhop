import Foundation

/// `--print-menu status.json` prints the menu the tray builds, on any system, for checking the
/// Windows menu without Windows. `--status-file` makes the real tray show saved data instead of
/// running switchr.exe, and `--show-menu` or `--show-dialog` open them for screenshots.
if let index = CommandLine.arguments.firstIndex(of: "--print-menu"), CommandLine.arguments.indices.contains(index + 1) {
    do {
        let status = try TrayStatus.decode(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1])))
        func show(_ items: [TrayMenuItem], depth: Int) {
            for item in items {
                let indent = String(repeating: "    ", count: depth)
                if item.isSeparator {
                    print("\(indent)  ----")
                    continue
                }
                let mark = item.checked ? "✓" : " "
                let note = item.isLabel ? "  (label)" : item.enabled ? "" : "  (disabled)"
                print("\(indent)\(mark) \(item.title.replacingOccurrences(of: "\t", with: "    "))\(item.children.isEmpty ? "" : "  ▸")\(note)")
                show(item.children, depth: depth + 1)
            }
        }
        show(TrayMenu.build(status: status, busy: nil, update: nil, settings: TraySettings(startsAtSignIn: true)), depth: 0)
        print("Tooltip: \(TrayMenu.tooltip(status).replacingOccurrences(of: "\n", with: " | "))")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Couldn't read the status: \(error)\n".utf8))
        exit(1)
    }
}

#if os(Windows)
TrayApp.shared.run()
#else
print("SwitchrTray is the Windows tray app. On Linux run switchr-tray; on macOS Switchr lives in the menu bar.")
#endif
