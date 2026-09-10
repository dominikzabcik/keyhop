import Charts
import SwiftUI

@MainActor
enum InsightsWindow {
    private static var window: NSWindow?

    static func show(store: AccountStore = .shared, tracker: UsageTracker = .shared, height: CGFloat = 780) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: height),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Insights"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.minSize = NSSize(width: 800, height: 600)
            window.contentView = NSHostingView(rootView: InsightsView().environmentObject(store).environmentObject(tracker))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Series colors in a fixed order. Every pair clears the color-vision and normal-vision
/// separation checks in light and dark mode, so hiding an account can never put two
/// look-alike colors side by side. Accounts past the fourth share the neutral "Other".
/// An account keeps its color by its place in Switchr, so filtering never repaints anyone.
enum ChartPalette {
    static let series: [Color] = ["#C9821A", "#2F6FC0", "#B8423F", "#1E9A78"].map(Color.init(hex:))
    static let other = Color(hex: "#8A8A86")
}

extension Color {
    init(hex: String) {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

extension Provider {
    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .codex: "Codex"
        }
    }
}

struct InsightsView: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var tracker: UsageTracker

    @State private var range: InsightsRange = .week
    @State private var provider: Provider?
    @State private var metric: Metric = .tokens
    @State private var digest: UsageDigest?
    @State private var hovered: Date?

    enum Metric: String, CaseIterable, Identifiable {
        case tokens, cost
        var id: String { rawValue }
        var title: String { self == .tokens ? "Tokens" : "API value" }
    }

    private struct Query: Equatable {
        let range: InsightsRange
        let provider: Provider?
        let revision: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                controls
                if let digest {
                    headline(digest)
                    chart(digest)
                    accountsTable(digest)
                    HStack(alignment: .top, spacing: 48) {
                        models(digest).frame(maxWidth: .infinity, alignment: .leading)
                        limits.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 50)
            .padding(.bottom, 40)
        }
        .background(Enamel())
        .environment(\.colorScheme, .dark)
        .task(id: Query(range: range, provider: provider, revision: tracker.revision)) {
            digest = await tracker.digest(range: range, provider: provider, sole: store.soleAccounts)
        }    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 14) {
            Picker("Range", selection: $range) {
                ForEach(InsightsRange.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 340)

            Picker("Tool", selection: $provider) {
                Text("All tools").tag(Provider?.none)
                ForEach(Provider.allCases) { Text($0.name).tag(Provider?.some($0)) }
            }
            .labelsHidden()
            .frame(width: 150)

            Spacer()
            if tracker.isUpdating {
                ProgressView().controlSize(.small)
            }
            Text(updatedText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var updatedText: String {
        if tracker.isUpdating { return "Reading usage logs" }
        guard let last = tracker.lastUpdate else { return tracker.problem ?? "Not read yet" }
        return "Updated \(last.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: Headline

    private func headline(_ digest: UsageDigest) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 48) {
            figure(Numbers.tokens(digest.total.tokens.total), caption: "tokens")
            figure(Numbers.usd(digest.total.cost), caption: "at API prices")
            if digest.total.billed > 0 {
                figure(Numbers.usd(digest.total.billed), caption: "billed on demand")
            }
            Spacer(minLength: 16)
            if let change = change(digest) {
                Text(change)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func figure(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Brand.bone)
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func change(_ digest: UsageDigest) -> String? {
        let before = Double(digest.previous.tokens.total)
        guard before > 0 else { return nil }
        let percent = Int(((Double(digest.total.tokens.total) - before) / before * 100).rounded())
        let comparison = switch range {
        case .today: "than yesterday"
        case .week: "than the 7 days before"
        case .month: "than the month before"
        case .thirtyDays: "than the 30 days before"
        }
        return percent == 0 ? "Same token use as \(comparison.dropFirst(5))" : "\(abs(percent))% \(percent > 0 ? "more" : "fewer") tokens \(comparison)"
    }

    // MARK: Chart

    private struct Series {
        let label: String
        let color: Color
    }

    private struct Segment: Identifiable {
        let start: Date
        let series: String
        let low: Double
        let high: Double
        let value: Double
        var id: String { "\(start.timeIntervalSince1970)|\(series)" }
    }

    private var unit: Calendar.Component { range.bucket == .hour ? .hour : .day }

    private func label(for key: AccountKey) -> String {
        guard let id = key.account, let index = store.accounts.firstIndex(where: { $0.id == id }) else { return "Earlier or removed" }
        // Past the palette, accounts share the neutral color, and a shared label, unless only one is left over.
        if index >= ChartPalette.series.count, store.accounts.count > ChartPalette.series.count + 1 { return "Other accounts" }
        let account = store.accounts[index]
        return "\(account.provider.shortName) · \(account.displayName)"
    }

    private func color(for key: AccountKey) -> Color {
        guard let id = key.account, let index = store.accounts.firstIndex(where: { $0.id == id }), index < ChartPalette.series.count else {
            return ChartPalette.other
        }
        return ChartPalette.series[index]
    }

    private func series(_ digest: UsageDigest) -> [Series] {
        let keys = digest.byAccount.keys.sorted { a, b in
            let ia = a.account.flatMap { id in store.accounts.firstIndex { $0.id == id } } ?? .max
            let ib = b.account.flatMap { id in store.accounts.firstIndex { $0.id == id } } ?? .max
            return ia < ib
        }
        var seen = Set<String>()
        return keys.compactMap { key in
            let label = label(for: key)
            guard seen.insert(label).inserted else { return nil }
            return Series(label: label, color: color(for: key))
        }
    }

    private func value(_ totals: Totals) -> Double {
        metric == .tokens ? Double(totals.tokens.total) : totals.cost
    }

    /// Stacks each bucket's accounts in series order, leaving a thin gap between segments.
    private func segments(_ digest: UsageDigest, order: [Series]) -> [Segment] {
        var byStart: [Date: [String: Double]] = [:]
        for point in digest.points {
            byStart[point.start, default: [:]][label(for: point.key), default: 0] += value(point.totals)
        }
        let tallest = byStart.values.map { $0.values.reduce(0, +) }.max() ?? 0
        let gap = tallest * 0.008
        var result: [Segment] = []
        for (start, values) in byStart {
            var floor = 0.0
            let present = order.filter { (values[$0.label] ?? 0) > 0 }
            for (i, entry) in present.enumerated() {
                let amount = values[entry.label] ?? 0
                let top = floor + amount
                let isLast = i == present.count - 1
                result.append(Segment(start: start, series: entry.label, low: floor, high: isLast ? top : max(floor, top - gap), value: amount))
                floor = top
            }
        }
        return result
    }

    private func chart(_ digest: UsageDigest) -> some View {
        let order = series(digest)
        let stacked = segments(digest, order: order)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(metric == .tokens ? "Tokens by account" : "API value by account")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Picker("Measure", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }

            if stacked.isEmpty {
                Text("No usage in this range yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart {
                    ForEach(stacked) { segment in
                        BarMark(
                            x: .value("Time", segment.start, unit: unit),
                            yStart: .value(metric.title, segment.low),
                            yEnd: .value(metric.title, segment.high),
                            width: .ratio(0.7)
                        )
                        .foregroundStyle(by: .value("Account", segment.series))
                        .cornerRadius(3)
                    }
                    if let hovered {
                        RuleMark(x: .value("Time", hovered, unit: unit))
                            .foregroundStyle(Color.primary.opacity(0.14))
                            .zIndex(-1)
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                tooltip(at: hovered, segments: stacked, order: order)
                            }
                    }
                }
                .chartForegroundStyleScale(domain: order.map(\.label), range: order.map(\.color))
                .chartLegend(position: .bottom, alignment: .leading, spacing: 16)
                .chartYAxis {
                    AxisMarks(position: .leading) { mark in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.07))
                        AxisValueLabel {
                            if let amount = mark.as(Double.self) {
                                Text(metric == .tokens ? Numbers.tokens(Int(amount)) : Numbers.usd(amount))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: range == .today ? 8 : 7)) { _ in
                        AxisValueLabel(format: range == .today ? .dateTime.hour() : .dateTime.month(.abbreviated).day())
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    guard let plot = proxy.plotFrame else { return }
                                    let x = location.x - geometry[plot].origin.x
                                    if let date: Date = proxy.value(atX: x) {
                                        hovered = Calendar.current.dateInterval(of: unit, for: date)?.start
                                    }
                                case .ended:
                                    hovered = nil
                                }
                            }
                    }
                }
                .frame(height: 260)
            }
        }
    }

    private func tooltip(at date: Date, segments: [Segment], order: [Series]) -> some View {
        let rows = order.compactMap { entry in segments.first { $0.start == date && $0.series == entry.label }.map { (entry, $0.value) } }
        return VStack(alignment: .leading, spacing: 5) {
            Text(date.formatted(range == .today ? .dateTime.hour().minute() : .dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.system(size: 11, weight: .semibold))
            if rows.isEmpty {
                Text("No usage")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.0.label) { entry, amount in
                HStack(spacing: 7) {
                    Circle().fill(entry.color).frame(width: 8, height: 8)
                    Text(entry.label).font(.system(size: 11))
                    Spacer(minLength: 12)
                    Text(metric == .tokens ? Numbers.tokens(Int(amount)) : Numbers.usd(amount))
                        .font(.system(size: 11).monospacedDigit())
                }
            }
        }
        .padding(10)
        .frame(minWidth: 210, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.regularMaterial))
    }

    // MARK: Accounts

    @ViewBuilder
    private func accountsTable(_ digest: UsageDigest) -> some View {
        let rows = store.accounts.filter { provider == nil || $0.provider == provider }
        VStack(alignment: .leading, spacing: 16) {
            Text("Accounts and budgets")
                .font(.system(size: 15, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
                GridRow {
                    columnHeader("Account")
                    columnHeader("Tokens").gridColumnAlignment(.trailing)
                    columnHeader("API value").gridColumnAlignment(.trailing)
                    columnHeader("Budget")
                }
                ForEach(rows) { account in
                    let key = AccountKey(provider: account.provider, account: account.id)
                    let totals = digest.byAccount[key] ?? Totals()
                    GridRow {
                        HStack(spacing: 9) {
                            Circle().fill(color(for: key)).frame(width: 8, height: 8)
                            ProviderMark(provider: account.provider).frame(width: 13, height: 13)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName).font(.system(size: 13))
                                Text([account.provider.name, account.plan].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(Numbers.tokens(totals.tokens.total)).font(.system(size: 13).monospacedDigit())
                        Text(Numbers.usd(totals.cost)).font(.system(size: 13).monospacedDigit())
                        BudgetCell(scope: Budget.scope(for: account.id))
                    }
                }
                if provider == nil {
                    GridRow {
                        Text("All accounts").font(.system(size: 13, weight: .semibold))
                        Text(Numbers.tokens(digest.total.tokens.total)).font(.system(size: 13, weight: .semibold).monospacedDigit())
                        Text(Numbers.usd(digest.total.cost)).font(.system(size: 13, weight: .semibold).monospacedDigit())
                        BudgetCell(scope: Budget.everything)
                    }
                }
            }
            Text("API value is what the tokens would cost at each provider's standard API prices. Subscriptions don't bill this way, so it measures how much use you get, not what you pay.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func columnHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }

    // MARK: Models

    @ViewBuilder
    private func models(_ digest: UsageDigest) -> some View {
        let top = Array(digest.byModel.sorted { $0.value.tokens.total > $1.value.tokens.total }.prefix(8))
        let largest = max(top.first?.value.tokens.total ?? 1, 1)
        VStack(alignment: .leading, spacing: 14) {
            Text("Models")
                .font(.system(size: 15, weight: .semibold))
            if top.isEmpty {
                Text("No usage in this range yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(top, id: \.key) { model, totals in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model).font(.system(size: 12.5))
                        Spacer(minLength: 12)
                        Text(Numbers.tokens(totals.tokens.total))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(Numbers.usd(totals.cost))
                            .font(.system(size: 12).monospacedDigit())
                            .frame(width: 70, alignment: .trailing)
                    }
                    ShareBar(fraction: Double(totals.tokens.total) / Double(largest))
                        .frame(height: 6)
                }
            }
        }
    }

    // MARK: Limits

    private var limits: some View {
        let signedIn = Provider.allCases.compactMap { provider in
            store.active[provider].flatMap { id in store.accounts.first { $0.id == id } }
        }
        return VStack(alignment: .leading, spacing: 14) {
            Text("Limits right now")
                .font(.system(size: 15, weight: .semibold))
            if signedIn.isEmpty {
                Text("No tool is signed in.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(signedIn) { account in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        ProviderMark(provider: account.provider).frame(width: 13, height: 13)
                        Text(account.displayName).font(.system(size: 13, weight: .medium))
                    }
                    ForEach(store.usage[account.id]?.windows ?? []) { window in
                        Text(limitLine(account, window))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func limitLine(_ account: Account, _ window: UsageWindow) -> String {
        var line = "\(window.label): \(Int(window.usedPercent.rounded()))% used"
        if let runsOut = tracker.forecasts[UsageTracker.forecastKey(account.id, window.label)], runsOut > Date() {
            line += ", runs out around \(runsOut.formatted(date: .omitted, time: .shortened))"
        } else if window.resetsAt != nil {
            line += ", resets in \(window.resetText(at: Date()))"
        }
        return line
    }
}

/// A neutral proportion bar; unlike the usage meter it carries no warning colors.
private struct ShareBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Color.primary.opacity(0.45))
                    .frame(width: max(geo.size.height, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
    }
}

private struct BudgetCell: View {
    @EnvironmentObject private var tracker: UsageTracker
    let scope: String
    @State private var editing = false

    var body: some View {
        let budget = tracker.budget(for: scope)
        Group {
            if let budget, budget.amount > 0 {
                let spent = tracker.budgetSpend[scope] ?? 0
                Button { editing = true } label: {
                    HStack(spacing: 10) {
                        Meter(fraction: spent / budget.amount, pace: budget.period.elapsed(at: Date()), emphasized: true)
                            .frame(width: 120, height: 10)
                        Text("\(Numbers.usd(spent)) of \(Numbers.usd(budget.amount)) \(budget.period.title)")
                            .font(.system(size: 12).monospacedDigit())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit budget")
            } else {
                QuietButton("Set budget") { editing = true }
            }
        }
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            BudgetEditor(scope: scope, budget: budget) { editing = false }
                .environmentObject(tracker)
        }
    }
}

private struct BudgetEditor: View {
    @EnvironmentObject private var tracker: UsageTracker
    let scope: String
    let budget: Budget?
    let close: () -> Void

    @State private var amount: String
    @State private var period: BudgetPeriod

    init(scope: String, budget: Budget?, close: @escaping () -> Void) {
        self.scope = scope
        self.budget = budget
        self.close = close
        _amount = State(initialValue: budget.map { String(format: "%g", $0.amount) } ?? "")
        _period = State(initialValue: budget?.period ?? .month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budget at API prices")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                Text("$")
                TextField("150", text: $amount)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .onSubmit(save)
                Picker("Period", selection: $period) {
                    ForEach(BudgetPeriod.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 120)
            }
            Text("Switchr notifies you at 80% and at 100%.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                if budget != nil {
                    Button("Remove") {
                        tracker.setBudget(nil, scope: scope)
                        close()
                    }
                }
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsedAmount == nil)
            }
        }
        .padding(16)
        .frame(width: 290)
    }

    private var parsedAmount: Double? {
        Double(amount.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
    }

    private func save() {
        guard let value = parsedAmount else { return }
        tracker.setBudget(Budget(scope: scope, amount: value, period: period), scope: scope)
        close()
    }
}
