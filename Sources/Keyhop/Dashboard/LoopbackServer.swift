import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import WinSDK
#endif

struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    /// Lowercased names.
    let headers: [String: String]
    let body: Data
}

struct HTTPResponse {
    var status: Int
    var headers: [String: String]
    var body: Data

    static func json<Value: Encodable>(_ value: Value, status: Int = 200) -> HTTPResponse {
        let data = (try? DashboardJSON.encoder.encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json; charset=utf-8"], body: data)
    }

    static func html(_ page: String) -> HTTPResponse {
        HTTPResponse(status: 200, headers: [
            "Content-Type": "text/html; charset=utf-8",
            // Everything the page needs is inline; it may only talk back to this server.
            "Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
        ], body: Data(page.utf8))
    }

    static func text(_ message: String, status: Int) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "text/plain; charset=utf-8"], body: Data(message.utf8))
    }
}

#if os(Windows)
typealias NativeSocket = SOCKET
#else
typealias NativeSocket = Int32
#endif

/// A minimal HTTP/1.1 server on 127.0.0.1: one request per connection, closed after the answer.
/// It exists only to serve the dashboard to a browser window on this computer.
final class LoopbackServer: @unchecked Sendable {
    let port: UInt16
    private let listener: NativeSocket
    private var running = true

    init(port requested: UInt16 = 0) throws {
        Sockets.startUp()
        let listener = Sockets.streamSocket()
        guard Sockets.isValid(listener) else { throw KeyhopError("Couldn't open a local socket for the dashboard.") }

        var address = sockaddr_in()
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        #if os(Windows)
        address.sin_family = ADDRESS_FAMILY(AF_INET)
        address.sin_addr.S_un.S_addr = UInt32(0x7F00_0001).bigEndian
        #else
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        #endif
        address.sin_port = requested.bigEndian

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Sockets.bind(listener, $0, MemoryLayout<sockaddr_in>.size) }
        }
        guard bound, Sockets.listen(listener) else {
            Sockets.close(listener)
            throw KeyhopError("Couldn't start the dashboard on this computer.")
        }

        var actual = sockaddr_in()
        withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Sockets.localAddress(listener, $0, MemoryLayout<sockaddr_in>.size) }
        }
        port = UInt16(bigEndian: actual.sin_port)
        self.listener = listener
    }

    /// Accepts connections on a background thread; each request is answered by `handler`.
    func start(_ handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) {
        let thread = Thread { [self] in
            while running {
                let client = Sockets.accept(listener)
                guard Sockets.isValid(client) else { continue }
                DispatchQueue.global().async {
                    guard let request = Self.read(client) else {
                        Self.write(.text("Bad request", status: 400), to: client)
                        Sockets.close(client)
                        return
                    }
                    Task {
                        let response = await handler(request)
                        DispatchQueue.global().async {
                            Self.write(response, to: client)
                            Sockets.close(client)
                        }
                    }
                }
            }
        }
        thread.start()
    }

    func stop() {
        running = false
        Sockets.close(listener)
    }

    // MARK: HTTP

    private static let maximumHeader = 64 * 1024
    private static let maximumBody = 1024 * 1024

    private static func read(_ client: NativeSocket) -> HTTPRequest? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        let separator = Data("\r\n\r\n".utf8)
        while true {
            if let end = buffer.range(of: separator) {
                guard let head = parseHead(buffer[buffer.startIndex..<end.lowerBound]) else { return nil }
                let length = Int(head.headers["content-length"] ?? "0") ?? 0
                guard length >= 0, length <= maximumBody else { return nil }
                while buffer.count - (end.upperBound - buffer.startIndex) < length {
                    let received = chunk.withUnsafeMutableBytes { Sockets.receive(client, $0) }
                    guard received > 0 else { return nil }
                    buffer.append(contentsOf: chunk[0..<received])
                }
                let bodyStart = end.upperBound
                let body = Data(buffer[bodyStart..<bodyStart + length])
                return HTTPRequest(method: head.method, path: head.path, query: head.query, headers: head.headers, body: body)
            }
            guard buffer.count < maximumHeader else { return nil }
            let received = chunk.withUnsafeMutableBytes { Sockets.receive(client, $0) }
            guard received > 0 else { return nil }
            buffer.append(contentsOf: chunk[0..<received])
        }
    }

    /// Parses the request line and headers of one HTTP/1.1 request.
    static func parseHead(_ data: Data) -> (method: String, path: String, query: [String: String], headers: [String: String])? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var lines = text.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return nil }
        let target = String(requestLine[1])
        guard target.hasPrefix("/"), let components = URLComponents(string: "http://127.0.0.1" + target) else { return nil }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return (String(requestLine[0]), components.path, query, headers)
    }

    private static func write(_ response: HTTPResponse, to client: NativeSocket) {
        let reason: String
        switch response.status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 409: reason = "Conflict"
        default: reason = "Error"
        }
        var head = "HTTP/1.1 \(response.status) \(reason)\r\n"
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        headers["Cache-Control"] = "no-store"
        headers["X-Content-Type-Options"] = "nosniff"
        headers["Referrer-Policy"] = "no-referrer"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        Sockets.sendAll(client, Data(head.utf8) + response.body)
    }
}

/// The few socket calls the server needs, the same on every system.
private enum Sockets {
    static func startUp() {
        #if os(Windows)
        var data = WSADATA()
        _ = WSAStartup(0x0202, &data)
        #else
        // A browser that closes early must not end the process.
        signal(SIGPIPE, SIG_IGN)
        #endif
    }

    static func streamSocket() -> NativeSocket {
        #if os(Windows)
        return socket(AF_INET, SOCK_STREAM, 6)
        #elseif canImport(Glibc)
        return socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        return socket(AF_INET, SOCK_STREAM, 0)
        #endif
    }

    static func isValid(_ socket: NativeSocket) -> Bool {
        #if os(Windows)
        return socket != ~SOCKET(0)
        #else
        return socket >= 0
        #endif
    }

    static func bind(_ socket: NativeSocket, _ address: UnsafePointer<sockaddr>, _ length: Int) -> Bool {
        #if os(Windows)
        return WinSDK.bind(socket, address, Int32(length)) == 0
        #elseif canImport(Darwin)
        return Darwin.bind(socket, address, socklen_t(length)) == 0
        #elseif canImport(Glibc)
        return Glibc.bind(socket, address, socklen_t(length)) == 0
        #else
        return Musl.bind(socket, address, socklen_t(length)) == 0
        #endif
    }

    static func listen(_ socket: NativeSocket) -> Bool {
        #if os(Windows)
        return WinSDK.listen(socket, 32) == 0
        #elseif canImport(Darwin)
        return Darwin.listen(socket, 32) == 0
        #elseif canImport(Glibc)
        return Glibc.listen(socket, 32) == 0
        #else
        return Musl.listen(socket, 32) == 0
        #endif
    }

    static func localAddress(_ socket: NativeSocket, _ address: UnsafeMutablePointer<sockaddr>, _ length: Int) {
        #if os(Windows)
        var size = Int32(length)
        _ = getsockname(socket, address, &size)
        #else
        var size = socklen_t(length)
        _ = getsockname(socket, address, &size)
        #endif
    }

    static func accept(_ socket: NativeSocket) -> NativeSocket {
        #if os(Windows)
        return WinSDK.accept(socket, nil, nil)
        #elseif canImport(Darwin)
        return Darwin.accept(socket, nil, nil)
        #elseif canImport(Glibc)
        return Glibc.accept(socket, nil, nil)
        #else
        return Musl.accept(socket, nil, nil)
        #endif
    }

    static func receive(_ socket: NativeSocket, _ buffer: UnsafeMutableRawBufferPointer) -> Int {
        #if os(Windows)
        return Int(recv(socket, buffer.baseAddress!.assumingMemoryBound(to: CChar.self), Int32(buffer.count), 0))
        #else
        return recv(socket, buffer.baseAddress, buffer.count, 0)
        #endif
    }

    static func sendAll(_ socket: NativeSocket, _ data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                #if os(Windows)
                let sent = Int(send(socket, base.advanced(by: offset).assumingMemoryBound(to: CChar.self), Int32(raw.count - offset), 0))
                #else
                let sent = send(socket, base.advanced(by: offset), raw.count - offset, 0)
                #endif
                guard sent > 0 else { return }
                offset += sent
            }
        }
    }

    static func close(_ socket: NativeSocket) {
        #if os(Windows)
        closesocket(socket)
        #elseif canImport(Darwin)
        Darwin.close(socket)
        #elseif canImport(Glibc)
        Glibc.close(socket)
        #else
        Musl.close(socket)
        #endif
    }
}
