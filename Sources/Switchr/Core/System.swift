import Foundation

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
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ShellResult(status: process.terminationStatus, stdout: stdout, stderr: String(decoding: stderr, as: UTF8.self))
    }
}

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

    /// Temp file + rename, so a crash never leaves a half-written credentials file. Keeps 0600.
    static func writeAtomically(_ data: Data, to url: URL) throws {
        let target = url.resolvingSymlinksInPath()
        let dir = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".\(target.lastPathComponent).switchr-\(UUID().uuidString)")
        try data.write(to: tmp)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        if rename(tmp.path, target.path) != 0 {
            try? FileManager.default.removeItem(at: tmp)
            throw SwitchrError("Couldn't write \(target.lastPathComponent)")
        }
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

    private static func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
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
