import Foundation

/// The Insights page for Linux and Windows, and `switchr insights` anywhere: one self-contained
/// HTML file. Every range and both measures are rendered up front, so the page reads fully
/// without JavaScript; the script only switches between them and shows hover details.
enum InsightsPage {
    struct RangeData {
        let range: InsightsRange
        let interval: DateInterval
        let digest: UsageDigest
    }

    struct Input {
        var generatedAt: Date
        var accounts: [Account]
        var active: [Provider: UUID]
        var usage: [UUID: UsageSnapshot]
        var ranges: [RangeData]
        var budgets: [Budget]
        var budgetSpend: [String: Double]
        var initial: InsightsRange
    }

    /// Same fixed order as the Mac app: validated for color-vision and normal-vision separation
    /// on the enamel surface. Accounts past the fourth share the neutral.
    static let seriesColors = ["#C9821A", "#2F6FC0", "#B8423F", "#1E9A78"]
    static let otherColor = "#8A8A86"

    enum Metric: String, CaseIterable {
        case tokens, cost
        var title: String { self == .tokens ? "Tokens" : "API value" }
    }

    struct Series: Hashable {
        let id: String
        let name: String
        let color: String
        let order: Int
    }

    // MARK: Page

    static func render(_ input: Input) -> String {
        let sections = input.ranges.map { rangeSection($0, input: input) }.joined(separator: "\n")
        let rangeButtons = input.ranges.map {
            #"<button type="button" data-set-range="\#($0.range.argument)" aria-pressed="\#($0.range == input.initial)">\#(escape($0.range.title))</button>"#
        }.joined()
        let metricButtons = Metric.allCases.map {
            #"<button type="button" data-set-metric="\#($0.rawValue)" aria-pressed="\#($0 == .tokens)">\#($0.title)</button>"#
        }.joined()
        let read = input.generatedAt.formatted(date: .abbreviated, time: .shortened)

        return #"""
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="dark">
        <title>Switchr Insights</title>
        <style>\#(css)</style>
        </head>
        <body>
        <main>
          <header class="masthead">
            \#(mark)
            <span class="brand">Switchr</span>
            <span class="read">Insights, read \#(escape(read))</span>
          </header>
          <div class="controls">
            <div class="seg" role="group" aria-label="Range"><span class="thumb" aria-hidden="true"></span>\#(rangeButtons)</div>
            <div class="seg" role="group" aria-label="Measure"><span class="thumb" aria-hidden="true"></span>\#(metricButtons)</div>
          </div>
          \#(sections)
          <div class="lower">
            \#(limitsBlock(input))
            \#(budgetsBlock(input))
          </div>
          <p class="footnote">API value prices every token at the provider's standard API rates, whatever plan paid for it. Regenerate this page with <code>switchr insights</code>.</p>
        </main>
        <div class="tip" role="tooltip" hidden></div>
        <script>\#(script(initial: input.initial.argument))</script>
        </body>
        </html>
        """#
    }

    private static func rangeSection(_ data: RangeData, input: Input) -> String {
        let digest = data.digest
        let hidden = data.range == input.initial ? "" : " hidden"
        let series = seriesList(digest, accounts: input.accounts)

        var body: String
        if digest.total.requests == 0 {
            body = #"<p class="empty">No usage in this range yet. Switchr reads Claude Code and Codex logs on this computer, and Cursor's usage export after a refresh.</p>"#
        } else {
            let legend = series.map {
                #"<li><span class="swatch" style="background:\#($0.color)"></span>\#(escape($0.name))</li>"#
            }.joined()
            let charts = Metric.allCases.map { metric in
                #"<div class="chart" data-metric="\#(metric.rawValue)"\#(metric == .tokens ? "" : " hidden")>\#(chart(data, metric: metric, input: input))</div>"#
            }.joined()
            body = #"""
            <ul class="legend">\#(legend)</ul>
            \#(charts)
            <div class="columns">
              \#(accountsBlock(digest, input: input))
              \#(modelsBlock(digest))
            </div>
            \#(numbersTable(data, input: input))
            """#
        }

        return #"""
        <section class="range" data-range="\#(data.range.argument)"\#(hidden)>
          <div class="hero">
            <p class="figure"><span data-metric="tokens">\#(Numbers.tokens(digest.total.tokens.total))<small> tokens</small></span><span data-metric="cost" hidden>\#(Numbers.usd(digest.total.cost))<small> API value</small></span></p>
            <p class="sub">\#(escape(summary(data)))</p>
          </div>
          \#(body)
        </section>
        """#
    }

    private static func summary(_ data: RangeData) -> String {
        let digest = data.digest
        var parts = ["\(Numbers.usd(digest.total.cost)) at API prices", "\(digest.total.requests.formatted()) requests"]
        if digest.total.billed > 0 { parts.append("\(Numbers.usd(digest.total.billed)) billed on demand") }
        var sentence = "\(data.range.title): " + parts.joined(separator: ", ") + "."
        let before = Double(digest.previous.tokens.total)
        if before > 0 {
            let change = Int(((Double(digest.total.tokens.total) - before) / before * 100).rounded())
            sentence += change == 0
                ? " The same as the period before."
                : " \(abs(change))% \(change > 0 ? "more" : "fewer") tokens than the period before."
        }
        return sentence
    }

    // MARK: Series

    static func series(for key: AccountKey, accounts: [Account]) -> Series {
        guard let id = key.account, let index = accounts.firstIndex(where: { $0.id == id }) else {
            return Series(id: "earlier-\(key.provider.rawValue)", name: "\(key.provider.shortName), earlier or removed", color: otherColor, order: 10_000)
        }
        if index >= seriesColors.count, accounts.count > seriesColors.count + 1 {
            return Series(id: "other", name: "Other accounts", color: otherColor, order: 9_000)
        }
        let account = accounts[index]
        return Series(id: account.id.uuidString, name: "\(account.provider.shortName), \(account.displayName)",
                      color: index < seriesColors.count ? seriesColors[index] : otherColor, order: index)
    }

    private static func seriesList(_ digest: UsageDigest, accounts: [Account]) -> [Series] {
        Set(digest.byAccount.keys.map { series(for: $0, accounts: accounts) }).sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }

    // MARK: Chart

    private static func buckets(_ data: RangeData) -> [Date] {
        let calendar = Calendar.current
        let component: Calendar.Component = data.range.bucket == .hour ? .hour : .day
        var result: [Date] = []
        var cursor = data.interval.start
        while cursor < data.interval.end, result.count < 800 {
            result.append(cursor)
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private static func chart(_ data: RangeData, metric: Metric, input: Input) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = data.range.bucket.dateFormat
        let starts = buckets(data)
        let order = seriesList(data.digest, accounts: input.accounts)

        var values: [String: [Series: Double]] = [:]
        for point in data.digest.points {
            let value = metric == .tokens ? Double(point.totals.tokens.total) : point.totals.cost
            values[formatter.string(from: point.start), default: [:]][series(for: point.key, accounts: input.accounts), default: 0] += value
        }

        let width = 920.0, height = 280.0
        let left = 58.0, right = 6.0, top = 14.0, bottom = 30.0
        let plotWidth = width - left - right, plotHeight = height - top - bottom
        let peak = starts.map { values[formatter.string(from: $0)]?.values.reduce(0, +) ?? 0 }.max() ?? 0
        let ceiling = niceCeiling(peak)
        let slot = plotWidth / Double(max(starts.count, 1))
        let barWidth = max(2, min(slot * 0.62, 36))

        func label(_ value: Double) -> String {
            metric == .tokens ? Numbers.tokens(Int(value.rounded())) : (value < 10 && value > 0 ? String(format: "$%.2f", value) : Numbers.usd(value))
        }
        func y(_ value: Double) -> Double { top + plotHeight - value / ceiling * plotHeight }

        var svg = #"<svg viewBox="0 0 \#(Int(width)) \#(Int(height))" role="img" aria-label="\#(escape(metric.title)) by \#(data.range.bucket == .hour ? "hour" : "day"), stacked by account">"#

        for step in 0...4 {
            let value = ceiling / 4 * Double(step)
            let lineY = fmt(y(value))
            svg += #"<line class="\#(step == 0 ? "base" : "grid")" x1="\#(fmt(left))" x2="\#(fmt(width - right))" y1="\#(lineY)" y2="\#(lineY)"/>"#
            svg += #"<text class="axis" x="\#(fmt(left - 10))" y="\#(lineY)" text-anchor="end" dominant-baseline="central">\#(label(value))</text>"#
        }

        let labelEvery: Int = {
            switch data.range {
            case .today: return 6
            case .week: return 1
            case .month, .thirtyDays: return 5
            }
        }()
        let axisFormatter = DateFormatter()
        axisFormatter.setLocalizedDateFormatFromTemplate(data.range == .today ? "HH" : data.range == .week ? "EEE d" : "MMM d")
        let tipFormatter = DateFormatter()
        tipFormatter.setLocalizedDateFormatFromTemplate(data.range == .today ? "EEE HH:mm" : "EEE MMM d")

        for (index, start) in starts.enumerated() {
            let centerX = left + slot * (Double(index) + 0.5)
            let x = centerX - barWidth / 2
            let column = values[formatter.string(from: start)] ?? [:]
            let present = order.filter { (column[$0] ?? 0) > 0 }

            var base = 0.0
            for (position, entry) in present.enumerated() {
                let value = column[entry] ?? 0
                let bottomY = y(base), topY = y(base + value)
                base += value
                // A 2px surface gap between stacked segments.
                let gap = position == 0 ? 0 : min(2, (bottomY - topY) / 2)
                let segmentBottom = bottomY - gap
                let segmentHeight = segmentBottom - topY
                guard segmentHeight > 0.2 else { continue }
                if position == present.count - 1 {
                    svg += #"<path d="\#(roundedTop(x: x, y: topY, width: barWidth, height: segmentHeight))" fill="\#(entry.color)"/>"#
                } else {
                    svg += #"<rect x="\#(fmt(x))" y="\#(fmt(topY))" width="\#(fmt(barWidth))" height="\#(fmt(segmentHeight))" fill="\#(entry.color)"/>"#
                }
            }

            if index % labelEvery == 0 {
                svg += #"<text class="axis" x="\#(fmt(centerX))" y="\#(fmt(height - 10))" text-anchor="middle">\#(escape(axisFormatter.string(from: start)))</text>"#
            }

            let rows = present.reversed().map { entry -> [String] in [entry.name, entry.color, label(column[entry] ?? 0)] }
            let rowsJSON = (try? JSONSerialization.data(withJSONObject: rows)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
            svg += #"<rect class="hit" x="\#(fmt(left + slot * Double(index)))" y="\#(fmt(top))" width="\#(fmt(slot))" height="\#(fmt(plotHeight))" data-label="\#(escape(tipFormatter.string(from: start)))" data-total="\#(escape(label(column.values.reduce(0, +))))" data-rows="\#(escape(rowsJSON))"/>"#
        }
        svg += "</svg>"
        return svg
    }

    /// A bar segment with a 4px rounded data end on top, square on its base.
    private static func roundedTop(x: Double, y: Double, width: Double, height: Double) -> String {
        let r = min(4, height, width / 2)
        return "M\(fmt(x)),\(fmt(y + height))V\(fmt(y + r))Q\(fmt(x)),\(fmt(y)) \(fmt(x + r)),\(fmt(y))H\(fmt(x + width - r))Q\(fmt(x + width)),\(fmt(y)) \(fmt(x + width)),\(fmt(y + r))V\(fmt(y + height))Z"
    }

    static func niceCeiling(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(value)))
        for step in [1.0, 2.0, 2.5, 5.0, 10.0] where step * magnitude >= value {
            return step * magnitude
        }
        return 10 * magnitude
    }

    // MARK: Blocks

    private static func accountsBlock(_ digest: UsageDigest, input: Input) -> String {
        let total = max(Double(digest.total.tokens.total), 1)
        let rows = digest.byAccount.sorted { $0.value.tokens.total > $1.value.tokens.total }.map { key, totals -> String in
            let entry = series(for: key, accounts: input.accounts)
            let account = key.account.flatMap { id in input.accounts.first { $0.id == id } }
            let share = Double(totals.tokens.total) / total
            let detail = [key.provider.name, account?.plan, account.flatMap { input.active[key.provider] == $0.id ? "in use" : nil }]
                .compactMap { $0 }.joined(separator: ", ")
            return #"""
            <li>
              <div class="line"><span class="name">\#(escape(account?.displayName ?? "Earlier or removed"))</span><span class="num"><span data-metric="tokens">\#(Numbers.tokens(totals.tokens.total))</span><span data-metric="cost" hidden>\#(Numbers.usd(totals.cost))</span></span></div>
              <div class="line meta"><span>\#(escape(detail))</span><span class="num">\#(Int((share * 100).rounded()))%</span></div>
              <div class="track"><span style="width:\#(fmt(max(share * 100, 1)))%;background:\#(entry.color)"></span></div>
            </li>
            """#
        }.joined()
        return #"<div class="block"><h2>Accounts</h2><ul class="rows">\#(rows)</ul></div>"#
    }

    private static func modelsBlock(_ digest: UsageDigest) -> String {
        let models = digest.byModel.sorted { $0.value.tokens.total > $1.value.tokens.total }
        let peak = max(Double(models.first?.value.tokens.total ?? 1), 1)
        let rows = models.prefix(8).map { model, totals -> String in
            #"""
            <li>
              <div class="line"><span class="name mono">\#(escape(model))</span><span class="num"><span data-metric="tokens">\#(Numbers.tokens(totals.tokens.total))</span><span data-metric="cost" hidden>\#(Numbers.usd(totals.cost))</span></span></div>
              <div class="track quiet"><span style="width:\#(fmt(max(Double(totals.tokens.total) / peak * 100, 1)))%"></span></div>
            </li>
            """#
        }.joined()
        let more = models.count > 8 ? #"<p class="more">\#(models.count - 8) more models</p>"# : ""
        return #"<div class="block"><h2>Models</h2><ul class="rows">\#(rows)</ul>\#(more)</div>"#
    }

    private static func limitsBlock(_ input: Input) -> String {
        let now = Date()
        var groups: [String] = []
        for provider in Provider.allCases {
            guard let id = input.active[provider], let account = input.accounts.first(where: { $0.id == id }) else { continue }
            let snapshot = input.usage[id]
            let windows = snapshot?.windows ?? []
            let rows = windows.map { window -> String in
                let used = min(max(window.usedPercent, 0), 100)
                let pace = window.pace(at: now).map { #"<i style="left:\#(fmt(min(max($0, 0), 1) * 100))%"></i>"# } ?? ""
                let reset = window.resetsAt == nil ? "" : "resets in \(window.resetText(at: now))"
                return #"""
                <li>
                  <div class="line"><span class="name">\#(escape(window.label))</span><span class="num">\#(Int(used.rounded()))%</span></div>
                  <div class="track limit"><span style="width:\#(fmt(max(used, 1)))%"></span>\#(pace)</div>
                  <div class="line meta"><span>\#(escape(reset))</span></div>
                </li>
                """#
            }.joined()
            let note = snapshot?.error.map { #"<p class="more">\#(escape($0))</p>"# } ?? (windows.isEmpty ? #"<p class="more">Limits not read yet. Run switchr refresh.</p>"# : "")
            groups.append(#"<div class="group"><h3>\#(escape(provider.name))<span>\#(escape(account.displayName))</span></h3><ul class="rows">\#(rows)</ul>\#(note)</div>"#)
        }
        let content = groups.isEmpty
            ? #"<p class="more">No tool has a saved account in use yet.</p>"#
            : groups.joined()
        return #"<div class="block"><h2>Limits now</h2>\#(content)<p class="more">The tick marks how much of each window has passed.</p></div>"#
    }

    private static func budgetsBlock(_ input: Input) -> String {
        guard !input.budgets.isEmpty else {
            return #"<div class="block"><h2>Budgets</h2><p class="more">No budgets yet. Set one with <code>switchr budget set all 200 --period month</code>; Switchr warns at 80% and 100%.</p></div>"#
        }
        let now = Date()
        let rows = input.budgets.map { budget -> String in
            let document = BudgetDocument(budget, spent: input.budgetSpend[budget.scope] ?? 0, accounts: input.accounts)
            let share = document.amount > 0 ? document.spent / document.amount : 0
            let elapsed = budget.period.elapsed(at: now)
            return #"""
            <li>
              <div class="line"><span class="name">\#(escape(document.name))</span><span class="num">\#(Numbers.usd(document.spent)) of \#(Numbers.usd(document.amount))</span></div>
              <div class="track limit\#(share >= 1 ? " over" : "")"><span style="width:\#(fmt(min(max(share * 100, 1), 100)))%"></span><i style="left:\#(fmt(elapsed * 100))%"></i></div>
              <div class="line meta"><span>\#(escape(budget.period.title.capitalized)), at API prices</span><span class="num">\#(Int((share * 100).rounded()))%</span></div>
            </li>
            """#
        }.joined()
        return #"<div class="block"><h2>Budgets</h2><ul class="rows">\#(rows)</ul></div>"#
    }

    private static func numbersTable(_ data: RangeData, input: Input) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = data.range.bucket.dateFormat
        let display = DateFormatter()
        display.setLocalizedDateFormatFromTemplate(data.range == .today ? "HH:mm" : "EEE MMM d")
        let order = seriesList(data.digest, accounts: input.accounts)
        var cells: [String: [Series: Int]] = [:]
        for point in data.digest.points {
            cells[formatter.string(from: point.start), default: [:]][series(for: point.key, accounts: input.accounts), default: 0] += point.totals.tokens.total
        }
        let head = order.map { "<th>\(escape($0.name))</th>" }.joined()
        let rows = buckets(data).compactMap { start -> String? in
            guard let column = cells[formatter.string(from: start)] else { return nil }
            let values = order.map { "<td>\(column[$0].map(Numbers.tokens) ?? "")</td>" }.joined()
            return "<tr><th scope=\"row\">\(escape(display.string(from: start)))</th>\(values)</tr>"
        }.joined()
        return #"<details class="numbers"><summary>Show the numbers</summary><div class="scroll"><table><thead><tr><th>\#(data.range.bucket == .hour ? "Hour" : "Day")</th>\#(head)</tr></thead><tbody>\#(rows)</tbody></table></div></details>"#
    }

    // MARK: Pieces

    /// The two limit tracks from Switchr's menu bar icon.
    private static let mark = #"""
    <svg class="mark" viewBox="0 0 22 18" aria-hidden="true"><rect x="1" y="3" width="20" height="4.5" rx="2.25" fill="#EDE7D9" fill-opacity=".22"/><rect x="1" y="3" width="13" height="4.5" rx="2.25" fill="#EDE7D9"/><rect x="1" y="10.5" width="20" height="4.5" rx="2.25" fill="#CF9F57" fill-opacity=".25"/><rect x="1" y="10.5" width="7" height="4.5" rx="2.25" fill="#CF9F57"/></svg>
    """#

    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static let css = #"""
    :root {
      --enamel-top: #1B3329; --enamel-bottom: #0A1510;
      --bone: #EDE7D9; --ink-2: rgba(237,231,217,.66); --ink-3: rgba(237,231,217,.44);
      --amber: #CF9F57; --rust: #D27A63;
      --lift: rgba(237,231,217,.045); --groove: rgba(237,231,217,.09);
      --display: ui-rounded, "SF Pro Rounded", "Segoe UI Variable Display", system-ui, sans-serif;
      --text: system-ui, -apple-system, "Segoe UI Variable Text", "Segoe UI", Cantarell, "Noto Sans", sans-serif;
      color-scheme: dark;
    }
    * { box-sizing: border-box; }
    html { background: var(--enamel-bottom); }
    body {
      margin: 0; min-height: 100vh; color: var(--bone); font: 14px/1.45 var(--text);
      background-color: var(--enamel-bottom);
      background-image:
        url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2' stitchTiles='stitch'/%3E%3CfeColorMatrix values='0 0 0 0 .93 0 0 0 0 .9 0 0 0 0 .85 0 0 0 .05 0'/%3E%3C/filter%3E%3Crect width='160' height='160' filter='url(%23n)'/%3E%3C/svg%3E"),
        linear-gradient(180deg, var(--enamel-top) 0, #12241D 520px, var(--enamel-bottom) 1100px);
      background-repeat: repeat, no-repeat;
      -webkit-font-smoothing: antialiased;
    }
    main { max-width: 1000px; margin: 0 auto; padding: 36px 40px 56px; }
    .masthead { display: flex; align-items: center; gap: 10px; }
    .mark { width: 22px; height: 18px; }
    .brand { font: 600 17px/1 var(--display); }
    .read { color: var(--ink-3); font-size: 13px; margin-left: 4px; }
    .controls { display: flex; flex-wrap: wrap; gap: 14px; margin: 34px 0 6px; }
    .seg { position: relative; display: inline-flex; padding: 3px; border-radius: 11px; background: var(--lift); }
    .seg button {
      position: relative; z-index: 1; border: 0; background: transparent; color: var(--ink-2);
      font: 600 13px/1 var(--text); padding: 9px 14px; border-radius: 8px; cursor: pointer;
      transition: color .16s ease;
    }
    .seg button:hover { color: var(--bone); }
    .seg button[aria-pressed="true"] { color: var(--bone); background: rgba(237,231,217,.08); }
    .seg button:focus-visible { outline: 2px solid var(--amber); outline-offset: 1px; }
    .seg .thumb { display: none; }
    .js .seg .thumb {
      display: block; position: absolute; top: 3px; bottom: 3px; left: 0; width: 0; border-radius: 8px;
      background: rgba(237,231,217,.09);
      box-shadow: inset 0 1px 0 rgba(237,231,217,.07);
    }
    .js .seg.ready .thumb { transition: transform .26s cubic-bezier(.3,.7,.2,1), width .26s cubic-bezier(.3,.7,.2,1); }
    .js .seg button[aria-pressed="true"] { background: transparent; }
    .hero { margin: 26px 0 22px; }
    .figure { margin: 0; font: 600 60px/1.05 var(--display); letter-spacing: -.005em; font-variant-numeric: tabular-nums; }
    .figure small { font: 500 20px/1 var(--display); color: var(--ink-3); letter-spacing: 0; }
    .sub { margin: 10px 0 0; color: var(--ink-2); font-size: 15px; max-width: 64ch; }
    .legend { list-style: none; margin: 0 0 10px; padding: 0; display: flex; flex-wrap: wrap; gap: 6px 18px; color: var(--ink-2); font-size: 12.5px; }
    .legend li { display: flex; align-items: center; gap: 7px; }
    .swatch { width: 14px; height: 4px; border-radius: 2px; }
    .chart { overflow-x: auto; margin: 0 -6px; }
    .chart svg { display: block; width: 100%; min-width: 640px; height: auto; }
    .chart .grid { stroke: rgba(237,231,217,.07); stroke-width: 1; stroke-linecap: round; }
    .chart .base { stroke: rgba(237,231,217,.2); stroke-width: 1; stroke-linecap: round; }
    .chart .axis { fill: var(--ink-3); font: 11px var(--text); font-variant-numeric: tabular-nums; }
    .chart .hit { fill: transparent; }
    .chart .hit:hover { fill: rgba(237,231,217,.04); }
    .columns, .lower { display: grid; grid-template-columns: 1fr 1fr; gap: 28px 56px; margin-top: 40px; }
    .block h2 { font: 600 15px/1.2 var(--display); margin: 0 0 14px; }
    .group + .group { margin-top: 18px; }
    .group h3 { font: 600 13px/1.2 var(--text); margin: 0 0 8px; display: flex; gap: 8px; align-items: baseline; }
    .group h3 span { color: var(--ink-3); font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .rows { list-style: none; margin: 0; padding: 0; display: grid; gap: 14px; }
    .line { display: flex; justify-content: space-between; gap: 16px; align-items: baseline; }
    .name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .mono { font-family: ui-monospace, "SF Mono", "Cascadia Mono", Consolas, monospace; font-size: 12.5px; }
    .num { font-variant-numeric: tabular-nums; white-space: nowrap; }
    .meta { color: var(--ink-3); font-size: 12px; margin-top: 2px; }
    .track { position: relative; height: 5px; border-radius: 3px; background: var(--groove); margin-top: 7px; }
    .track span { position: absolute; left: 0; top: 0; bottom: 0; border-radius: 3px; }
    .track.quiet span { background: rgba(237,231,217,.42); }
    .track.limit span { background: var(--bone); }
    .track.limit.over span { background: var(--rust); }
    .track i { position: absolute; top: -3px; width: 2px; height: 11px; border-radius: 1px; background: var(--amber); transform: translateX(-1px); }
    .more, .empty { color: var(--ink-3); font-size: 13px; margin: 12px 0 0; }
    .empty { font-size: 15px; color: var(--ink-2); margin: 8px 0 0; }
    code { font: 12.5px ui-monospace, "SF Mono", "Cascadia Mono", Consolas, monospace; color: var(--bone); background: var(--lift); padding: 1px 5px; border-radius: 5px; white-space: nowrap; }
    .numbers { margin-top: 30px; }
    .numbers summary { cursor: pointer; color: var(--ink-2); font-size: 13px; width: max-content; }
    .numbers summary:hover { color: var(--bone); }
    .scroll { overflow-x: auto; margin-top: 12px; }
    table { border-collapse: collapse; font-size: 12.5px; font-variant-numeric: tabular-nums; min-width: 100%; }
    th, td { text-align: right; padding: 5px 12px; white-space: nowrap; }
    th:first-child { text-align: left; padding-left: 0; }
    thead th { color: var(--ink-3); font-weight: 500; }
    tbody tr:nth-child(odd) { background: rgba(237,231,217,.025); }
    tbody th { font-weight: 500; color: var(--ink-2); }
    .footnote { margin: 48px 0 0; color: var(--ink-3); font-size: 12.5px; max-width: 72ch; }
    .tip {
      position: fixed; z-index: 10; pointer-events: none; min-width: 180px; max-width: 320px;
      padding: 10px 12px; border-radius: 10px; background: #0E1C17; color: var(--bone); font-size: 12.5px;
      box-shadow: 0 2px 6px rgba(4,10,8,.45), inset 0 1px 0 rgba(237,231,217,.06);
    }
    .tip b { display: block; font-weight: 600; margin-bottom: 6px; }
    .tip div { display: flex; align-items: center; gap: 8px; margin-top: 3px; }
    .tip div span:nth-child(2) { flex: 1; color: var(--ink-2); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .tip div span:last-child { font-variant-numeric: tabular-nums; }
    .tip .swatch { flex: none; }
    [hidden] { display: none !important; }
    @media (max-width: 760px) {
      main { padding: 24px 20px 40px; }
      .columns, .lower { grid-template-columns: 1fr; }
      .figure { font-size: 44px; }
    }
    @media (prefers-reduced-motion: reduce) { .js .seg.ready .thumb { transition: none; } }
    """#

    private static func script(initial: String) -> String {
        #"""
        (function () {
          var doc = document.documentElement;
          doc.classList.add("js");
          var state = { range: "\#(initial)", metric: "tokens" };
          try {
            var saved = JSON.parse(localStorage.getItem("switchr-insights") || "{}");
            if (saved.metric === "cost" || saved.metric === "tokens") state.metric = saved.metric;
          } catch (e) {}

          function place(seg) {
            var thumb = seg.querySelector(".thumb");
            var on = seg.querySelector('button[aria-pressed="true"]');
            if (!thumb || !on) return;
            thumb.style.width = on.offsetWidth + "px";
            thumb.style.transform = "translateX(" + on.offsetLeft + "px)";
          }

          function apply() {
            document.querySelectorAll("[data-range]").forEach(function (el) { el.hidden = el.getAttribute("data-range") !== state.range; });
            document.querySelectorAll("[data-metric]").forEach(function (el) { el.hidden = el.getAttribute("data-metric") !== state.metric; });
            document.querySelectorAll("[data-set-range]").forEach(function (b) { b.setAttribute("aria-pressed", b.getAttribute("data-set-range") === state.range); });
            document.querySelectorAll("[data-set-metric]").forEach(function (b) { b.setAttribute("aria-pressed", b.getAttribute("data-set-metric") === state.metric); });
            document.querySelectorAll(".seg").forEach(place);
            try { localStorage.setItem("switchr-insights", JSON.stringify({ metric: state.metric })); } catch (e) {}
          }

          document.addEventListener("click", function (event) {
            var button = event.target.closest("button");
            if (!button) return;
            if (button.hasAttribute("data-set-range")) state.range = button.getAttribute("data-set-range");
            if (button.hasAttribute("data-set-metric")) state.metric = button.getAttribute("data-set-metric");
            apply();
          });

          apply();
          requestAnimationFrame(function () { document.querySelectorAll(".seg").forEach(function (s) { s.classList.add("ready"); }); });
          window.addEventListener("resize", function () { document.querySelectorAll(".seg").forEach(place); });

          var tip = document.querySelector(".tip");
          function text(value) { var span = document.createElement("span"); span.textContent = value; return span; }
          document.addEventListener("pointermove", function (event) {
            var hit = event.target.closest && event.target.closest(".hit");
            if (!hit) { tip.hidden = true; return; }
            var rows = [];
            try { rows = JSON.parse(hit.getAttribute("data-rows")); } catch (e) {}
            tip.textContent = "";
            var title = document.createElement("b");
            title.textContent = hit.getAttribute("data-label") + ", " + hit.getAttribute("data-total");
            tip.appendChild(title);
            if (!rows.length) {
              tip.appendChild(text("No usage"));
            }
            rows.forEach(function (row) {
              var line = document.createElement("div");
              var swatch = document.createElement("span");
              swatch.className = "swatch";
              swatch.style.background = row[1];
              line.appendChild(swatch);
              line.appendChild(text(row[0]));
              line.appendChild(text(row[2]));
              tip.appendChild(line);
            });
            tip.hidden = false;
            var box = tip.getBoundingClientRect();
            var x = event.clientX + 16, y = event.clientY + 16;
            if (x + box.width > window.innerWidth - 8) x = event.clientX - box.width - 16;
            if (y + box.height > window.innerHeight - 8) y = event.clientY - box.height - 16;
            tip.style.left = Math.max(8, x) + "px";
            tip.style.top = Math.max(8, y) + "px";
          });
          document.addEventListener("pointerleave", function () { tip.hidden = true; });
        })();
        """#
    }
}
