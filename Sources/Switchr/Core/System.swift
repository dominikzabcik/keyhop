import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if os(Windows)
import WinSDK
#endif

#if !canImport(ObjectiveC)
/// Linux and Windows have no autorelease pools, so the body simply runs.
func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result {
    try body()
}
#endif

struct ShellResult {
    let status: Int32
    let stdout: Data
    let stderr: String
}

enum Shell {
    static func run(_ path: String, _ args: [String], stdin: Data? = nil) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let out = Pipe(), err = Pipe(), input = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = stdin == nil ? FileHandle.nullDevice : input
        try process.run()
        if let stdin {
            input.fileHandleForWriting.write(stdin)
            try? input.fileHandleForWriting.close()
        }
        // Read stderr alongside stdout, so a chatty program can't fill one pipe and stall.
        final class Box: @unchecked Sendable { var data = Data() }
        let errors = Box()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            errors.data = err.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        drained.wait()
        process.waitUntilExit()
        return ShellResult(status: process.terminationStatus, stdout: stdout, stderr: String(decoding: errors.data, as: UTF8.self))
    }

    /// Runs a program attached to this terminal, so tools like `sudo` can prompt.
    static func runInteractive(_ path: String, _ args: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Finds an executable on PATH, or in the usual system folders.
    static func which(_ name: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        #if os(Windows)
        let path = environment["PATH"] ?? environment["Path"] ?? ""
        let root = environment["SystemRoot"] ?? "C:\\Windows"
        let folders = path.split(separator: ";").map(String.init) + [root + "\\System32"]
        let extensions = name.contains(".") ? [""] : [".exe", ".cmd", ".bat", ""]
        for folder in folders where !folder.isEmpty {
            for ext in extensions {
                let candidate = URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent(name + ext).path
                if FileManager.default.fileExists(atPath: candidate) { return candidate }
            }
        }
        return nil
        #else
        let path = environment["PATH"] ?? ""
        let folders = path.split(separator: ":").map(String.init) + ["/usr/local/bin", "/usr/bin", "/bin"]
        return folders.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
        #endif
    }

    /// Starts a program that keeps running after Switchr exits. On Linux it gets its own session,
    /// so closing the terminal that ran `switchr` doesn't take it down.
    static func launchDetached(_ path: String, _ args: [String]) {
        let process = Process()
        #if os(Linux)
        if let setsid = which("setsid") {
            process.executableURL = URL(fileURLWithPath: setsid)
            process.arguments = [path] + args
        } else {
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
        }
        #else
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        #endif
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

/// Opening files and links with whatever the desktop uses for them.
enum Desktop {
    static func open(_ target: String) -> Bool {
        #if os(macOS)
        Shell.launchDetached("/usr/bin/open", [target])
        return true
        #elseif os(Windows)
        // rundll32 takes the URL as one argument, so `&` in a query string survives, unlike `start`.
        guard let rundll = Shell.which("rundll32.exe") else { return false }
        Shell.launchDetached(rundll, ["url.dll,FileProtocolHandler", target])
        return true
        #else
        guard let opener = Shell.which("xdg-open") ?? Shell.which("gio") else { return false }
        Shell.launchDetached(opener, opener.hasSuffix("gio") ? ["open", target] : [target])
        return true
        #endif
    }
}

enum Terminal {
    static var outputIsInteractive: Bool {
        #if os(Windows)
        return _isatty(1) != 0
        #else
        return isatty(STDOUT_FILENO) == 1
        #endif
    }

    static var inputIsInteractive: Bool {
        #if os(Windows)
        return _isatty(0) != 0
        #else
        return isatty(STDIN_FILENO) == 1
        #endif
    }
}

#if os(macOS)
/// Talks to the login keychain through /usr/bin/security. Items the provider CLIs create
/// already trust that binary, so reading and updating them never raises an access prompt,
/// and our own vault items stay prompt-free across rebuilds with a changing signature.
enum Keychain {
    private static let tool = "/usr/bin/security"

    static func read(service: String, account: String?) -> Data? {
        var args = ["find-generic-password", "-s", service, "-w"]
        if let account { args += ["-a", account] }
        guard let result = try? Shell.run(tool, args), result.status == 0 else { return nil }
        var data = result.stdout
        while data.last == 0x0A { data.removeLast() }
        return data
    }

    /// Passed as hex so any bytes survive. `security -i` would keep it off argv, but its
    /// interactive parser splits long lines, which breaks real credential blobs.
    static func write(service: String, account: String, data: Data) throws {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        let result = try Shell.run(tool, ["add-generic-password", "-U", "-a", account, "-s", service, "-X", hex])
        guard result.status == 0 else {
            throw SwitchrError("Keychain write failed for \(service)")
        }
    }

    static func delete(service: String, account: String) {
        _ = try? Shell.run(tool, ["delete-generic-password", "-s", service, "-a", account])
    }
}
#endif

enum JSON {
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func object(_ string: String?) -> [String: Any]? {
        string.flatMap { object(Data($0.utf8)) }
    }

    static func data(_ object: Any, pretty: Bool = false) throws -> Data {
        var options: JSONSerialization.WritingOptions = [.withoutEscapingSlashes]
        if pretty { options.insert(.prettyPrinted) }
        return try JSONSerialization.data(withJSONObject: object, options: options)
    }

    static func string(_ object: Any, pretty: Bool = false) throws -> String {
        String(decoding: try data(object, pretty: pretty), as: UTF8.self)
    }

    static func number(_ any: Any?) -> Double? {
        (any as? NSNumber)?.doubleValue ?? (any as? String).flatMap(Double.init)
    }
}

enum Files {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Temp file + rename, so a crash never leaves a half-written credentials file. Keeps 0600
    /// where files have POSIX permissions; on Windows the user's profile folder already is private.
    static func writeAtomically(_ data: Data, to url: URL) throws {
        let target = url.resolvingSymlinksInPath()
        let dir = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".\(target.lastPathComponent).switchr-\(UUID().uuidString)")
        try data.write(to: tmp)
        #if os(Windows)
        let moved = tmp.path.withCString(encodedAs: UTF16.self) { from in
            target.path.withCString(encodedAs: UTF16.self) { to in
                MoveFileExW(from, to, DWORD(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
            }
        }
        if !moved {
            try? FileManager.default.removeItem(at: tmp)
            throw SwitchrError("Couldn't write \(target.lastPathComponent)")
        }
        #else
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        if rename(tmp.path, target.path) != 0 {
            try? FileManager.default.removeItem(at: tmp)
            throw SwitchrError("Couldn't write \(target.lastPathComponent)")
        }
        #endif
    }
}

enum HTTP {
    static func get(_ url: String, headers: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 20)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await send(request)
    }

    static func postJSON(_ url: String, body: [String: Any]) async throws -> (Data, Int) {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSON.data(body)
        return try await send(request)
    }

    /// Built on the completion-handler API, which every Foundation (Apple's, Linux's, Windows') has.
    static func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data ?? Data(), (response as? HTTPURLResponse)?.statusCode ?? 0))
                }
            }.resume()
        }
    }
}

enum Dates {
    static func parse(_ any: Any?) -> Date? {
        if let n = JSON.number(any) {
            return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
        }
        guard let string = any as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        // Microsecond precision trips the formatter, so drop the fraction and retry.
        let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return f.date(from: trimmed)
    }
}

enum JWT {
    static func claims(_ token: String?) -> [String: Any]? {
        guard let parts = token?.split(separator: "."), parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        return Data(base64Encoded: b64).flatMap { JSON.object($0) }
    }

    static func expiry(_ token: String?) -> Date? {
        JSON.number(claims(token)?["exp"]).map { Date(timeIntervalSince1970: $0) }
    }
}
