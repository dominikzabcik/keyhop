import XCTest
@testable import Keyhop

/// Reading the providers' status pages.
final class ServiceStatusTests: XCTestCase {
    private let page = ServiceStatus.Page(name: "OpenAI", url: "https://status.openai.com", components: ["CLI", "Codex API"])

    private func summary(components: [(String, String)], incidents: String = "[]", maintenance: String = "[]") -> Data {
        let list = components.map { #"{"name":"\#($0.0)","status":"\#($0.1)"}"# }.joined(separator: ",")
        return Data(#"{"page":{"name":"OpenAI"},"components":[\#(list)],"incidents":\#(incidents),"scheduled_maintenances":\#(maintenance)}"#.utf8)
    }

    func testAllWorkingIsOperational() {
        let health = ServiceStatus.parse(summary(components: [("CLI", "operational"), ("Codex API", "operational")]), tool: .codex, page: page)
        XCTAssertEqual(health.level, .operational)
        XCTAssertFalse(health.isTrouble)
    }

    func testTroubleElsewhereOnThePageIsIgnored() {
        // Sora being down says nothing about Codex.
        let data = summary(components: [("CLI", "operational"), ("Sora", "major_outage")],
                           incidents: #"[{"name":"Sora is down","status":"investigating","impact":"critical","components":[{"name":"Sora"}]}]"#)
        let health = ServiceStatus.parse(data, tool: .codex, page: page)
        XCTAssertEqual(health.level, .operational)
        XCTAssertTrue(health.incidents.isEmpty)
    }

    func testTheWorstOfTheToolsComponentsWins() {
        let health = ServiceStatus.parse(summary(components: [("CLI", "degraded_performance"), ("Codex API", "partial_outage")]), tool: .codex, page: page)
        XCTAssertEqual(health.level, .partialOutage)
    }

    func testAnOpenIncidentOnTheToolIsCarriedWithItsImpact() {
        let data = summary(components: [("CLI", "operational")],
                           incidents: #"[{"name":"Elevated errors","status":"identified","impact":"major","updated_at":"2026-09-21T10:00:00.000Z","shortlink":"https://stspg.io/x","components":[{"name":"CLI"}]}]"#)
        let health = ServiceStatus.parse(data, tool: .codex, page: page)
        XCTAssertEqual(health.level, .partialOutage, "an incident can be worse than the components still say")
        XCTAssertEqual(health.incidents.first?.name, "Elevated errors")
        XCTAssertEqual(health.incidents.first?.stage, "identified")
        XCTAssertEqual(health.incidents.first?.link, "https://stspg.io/x")
        XCTAssertNotNil(health.incidents.first?.updated)
    }

    func testAnIncidentNamingNoComponentsCounts() {
        let data = summary(components: [("CLI", "operational")],
                           incidents: #"[{"name":"Something's wrong","status":"investigating","impact":"minor","components":[]}]"#)
        XCTAssertEqual(ServiceStatus.parse(data, tool: .codex, page: page).level, .degraded)
    }

    func testMaintenanceCountsOnlyWhileInProgress() {
        let planned = #"[{"name":"Database upgrade","status":"scheduled","impact":"maintenance","components":[{"name":"CLI"}]}]"#
        XCTAssertEqual(ServiceStatus.parse(summary(components: [("CLI", "operational")], maintenance: planned), tool: .codex, page: page).level, .operational)
        let running = planned.replacingOccurrences(of: "scheduled", with: "in_progress")
        let health = ServiceStatus.parse(summary(components: [("CLI", "operational")], maintenance: running), tool: .codex, page: page)
        XCTAssertEqual(health.level, .maintenance)
        XCTAssertEqual(health.incidents.first?.stage, "in progress")
    }

    func testAnUnreadablePageIsUnknownRatherThanFine() {
        let health = ServiceStatus.parse(Data("<html>".utf8), tool: .codex, page: page)
        XCTAssertEqual(health.level, .unknown)
        XCTAssertFalse(health.isTrouble, "not knowing isn't an outage")
    }

    func testTheMostTroubledComeFirst() {
        let sorted = ServiceStatus.sorted(SampleData.services())
        XCTAssertEqual(sorted.first?.tool, "codex")
        XCTAssertEqual(sorted.dropFirst().map(\.tool), ["claude", "cursor", "copilot", "windsurf"])
    }
}
