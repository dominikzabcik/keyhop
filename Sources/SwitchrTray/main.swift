import Foundation

#if os(Windows)
TrayApp.shared.run()
#else
if let index = CommandLine.arguments.firstIndex(of: "--print-menu"), CommandLine.arguments.indices.contains(index + 1) {
    // For checking the Windows menu from any system: SwitchrTray --print-menu status.json
    do {
        let status = try TrayStatus.decode(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1])))
        for item in TrayMenu.build(status: status, busy: nil, update: nil, startsAtSignIn: true) {
            if item.isSeparator {
                print("  ----")
            } else {
                print("\(item.checked ? "✓" : " ") \(item.title.replacingOccurrences(of: "\t", with: "    "))\(item.enabled ? "" : "  (label)")")
            }
        }
        print("Tooltip: \(TrayMenu.tooltip(status).replacingOccurrences(of: "\n", with: " | "))")
    } catch {
        FileHandle.standardError.write(Data("Couldn't read the status: \(error)\n".utf8))
        exit(1)
    }
} else {
    print("SwitchrTray is the Windows tray app. On Linux run switchr-tray; on macOS Switchr lives in the menu bar.")
}
#endif
