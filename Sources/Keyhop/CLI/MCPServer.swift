import Foundation

enum MCPServer {
    private static let latestProtocol = "2025-11-25"
    private static let supportedProtocols = [latestProtocol, "2025-06-18", "2024-11-05"]

    static func run(_ args: inout Arguments) async throws {
        try args.finish()
        while let line = readLine() {
            guard let request = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                write(error(id: NSNull(), code: -32700, message: "Parse error"))
                continue
            }
            if let response = await response(to: request) { write(response) }
        }
    }

    static func response(to request: [String: Any]) async -> [String: Any]? {
        let id = request["id"]
        guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
            return id.map { error(id: $0, code: -32600, message: "Invalid request") }
        }
        if id == nil { return nil }
        switch method {
        case "initialize":
            let params = request["params"] as? [String: Any]
            let requested = params?["protocolVersion"] as? String
            let version = requested.flatMap { supportedProtocols.contains($0) ? $0 : nil } ?? latestProtocol
            return success(id: id!, result: [
                "protocolVersion": version,
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "keyhop", "version": AppVersion.current],
                "instructions": "Read local Keyhop account health and usage. No tool exposes credentials or changes accounts.",
            ])
        case "ping":
            return success(id: id!, result: [:])
        case "tools/list":
            return success(id: id!, result: ["tools": tools])
        case "tools/call":
            guard let params = request["params"] as? [String: Any], let name = params["name"] as? String else {
                return error(id: id!, code: -32602, message: "tools/call needs a tool name")
            }
            guard toolNames.contains(name) else {
                return error(id: id!, code: -32602, message: "Unknown tool: \(name)")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                return success(id: id!, result: try await call(name: name, arguments: arguments))
            } catch let problem as UsageError {
                return success(id: id!, result: toolError(problem.message))
            } catch {
                return success(id: id!, result: toolError(error.localizedDescription))
            }
        default:
            return error(id: id!, code: -32601, message: "Method not found: \(method)")
        }
    }

    private static let tools: [[String: Any]] = [
        tool(
            name: "keyhop_status",
            title: "Keyhop status",
            description: "Read saved accounts, active accounts, current limit snapshots, budgets, alerts and Smart Hop recommendations.",
            properties: [:]
        ),
        tool(
            name: "keyhop_usage",
            title: "Keyhop usage",
            description: "Read cached local token, request and API-value history for a time range, grouped by tool, account, model, model maker and project folder. This never reads prompts or source code.",
            properties: [
                "range": ["type": "string", "default": "week",
                          "description": "today, week, month, 30d, 90d, 12m, all, or two dates as 2026-01-01..2026-03-31"],
                "tool": ["type": "string", "enum": Provider.allCases.map(\.rawValue)],
            ]
        ),
        tool(
            name: "keyhop_recommendation",
            title: "Smart Hop recommendation",
            description: "Choose the best current account runway from remaining limits, forecasts, reset timing and budgets.",
            properties: ["tool": ["type": "string", "enum": Provider.allCases.map(\.rawValue)]]
        ),
        tool(
            name: "keyhop_services",
            title: "Provider service status",
            description: "Read whether Anthropic, OpenAI, Cursor, GitHub and Windsurf report an outage, degraded performance or maintenance for the services these tools depend on, from their public status pages. An outage affects every account, so switching accounts doesn't help during one.",
            properties: [:],
            openWorld: true
        ),
    ]
    private static let toolNames = Set(tools.compactMap { $0["name"] as? String })

    private static func tool(name: String, title: String, description: String, properties: [String: Any], openWorld: Bool = false) -> [String: Any] {
        [
            "name": name,
            "title": title,
            "description": description,
            "inputSchema": ["type": "object", "properties": properties, "additionalProperties": false],
            "annotations": ["readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": openWorld],
            "execution": ["taskSupport": "forbidden"],
        ]
    }

    private static func call(name: String, arguments: [String: Any]) async throws -> [String: Any] {
        let allowed = Set(name == "keyhop_usage" ? ["range", "tool"] : name == "keyhop_recommendation" ? ["tool"] : [])
        guard Set(arguments.keys).isSubset(of: allowed) else { throw UsageError("This tool received an unknown argument.") }
        let workspace = try Workspace.open()
        switch name {
        case "keyhop_status":
            return try result(StatusDocument(try await Commands.currentOverview(workspace)))
        case "keyhop_usage":
            let word = arguments["range"] as? String ?? "week"
            guard let asked = InsightsRange(argument: word) else {
                throw UsageError("range must be today, week, month, 30d, 90d, 12m, all, or dates as 2026-01-01..2026-03-31")
            }
            let provider = try provider(in: arguments)
            let range = asked.resolved(firstUse: try await workspace.tracker.firstUse(provider: provider))
            let now = Date()
            let sole = await workspace.service.soleAccounts
            let digest = try await workspace.tracker.digest(interval: range.interval(now: now), previous: range.previous(now: now),
                                                            bucket: range.bucket, provider: provider, sole: sole)
            var report = digest
            report.sessions = (try? await workspace.tracker.sessions(in: range.interval(now: now), provider: provider, sole: sole)) ?? []
            let accounts = await workspace.service.accounts
            let budgets = try await workspace.tracker.budgets()
            let spend = try await workspace.tracker.budgetSpend(for: budgets, now: now, sole: sole)
            return try result(UsageDocument(range: range, now: now, digest: report, accounts: accounts, budgets: budgets, spend: spend))
        case "keyhop_services":
            let tools = Set(await workspace.service.accounts.map(\.provider))
            return try result(await ServiceStatus.check(tools.isEmpty ? Provider.allCases : Provider.allCases.filter(tools.contains)))
        case "keyhop_recommendation":
            let overview = try await Commands.currentOverview(workspace)
            return try result(RecommendationListDocument(overview, provider: try provider(in: arguments)))
        default:
            throw UsageError("Unknown tool: \(name)")
        }
    }

    private static func provider(in arguments: [String: Any]) throws -> Provider? {
        guard let value = arguments["tool"] else { return nil }
        guard let word = value as? String, let provider = Provider(rawValue: word) else {
            throw UsageError("tool must be claude, cursor, codex or gemini")
        }
        return provider
    }

    private static func result<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let data = try Output.encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        let text = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        return ["content": [["type": "text", "text": text]], "structuredContent": object]
    }

    private static func toolError(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    private static func success(id: Any, result: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private static func write(_ response: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}
