#if os(macOS)
import ServiceManagement
import SwiftUI

/// The menu bar panel: today's figure, the hop sentence, and the same login card as Overview.
struct MenuView: View {
    @EnvironmentObject private var store: AccountStore
    @State private var renaming: UUID?
    @State private var pet: CloudPet?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBoard(renaming: $renaming)

            if let pet {
                MenuPet(pet: pet)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            if let notice = store.notice {
                NoticeLine(text: notice)
            }

            UpdateLine()

            MenuFooter()
        }
        .frame(width: 520)
        .background(Brand.background)
        .environment(\.colorScheme, .dark)
        .task { await loadPet() }
    }

    /// A failed load leaves the menu able to switch accounts. The status icon stays the limit glyph.
    private func loadPet() async {
        guard let link = CloudLink.load() else {
            pet = nil
            return
        }
        if let loaded = try? await CloudClient(server: link.server, token: link.token).pet() {
            pet = loaded
        }
    }
}

private struct MenuPet: View {
    let pet: CloudPet

    var body: some View {
        HStack(spacing: 8) {
            Text(pet.caption)
                .foregroundStyle(Brand.muted)
            Spacer(minLength: 8)
            if let next = pet.next {
                Text("\(Numbers.tokens(next.tokens)) to \(next.label)")
                    .foregroundStyle(Brand.subtle)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Board

/// Today's total, the same sentence as Overview, and every login in the window's groups.
private struct MenuBoard: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var tracker: UsageTracker
    @Environment(\.staticSnapshot) private var staticSnapshot
    @Binding var renaming: UUID?
    @State private var showAdd = false

    var body: some View {
        let facts = MenuFacts.make(store: store, tracker: tracker)
        VStack(alignment: .leading, spacing: 0) {
            header(facts)
            if staticSnapshot {
                rows(facts)
            } else {
                FittingScroll(maxHeight: listCap) { rows(facts) }
            }
        }
    }

    /// The card stays a card. Extra logins scroll inside it.
    private var listCap: CGFloat { 380 }

    private func rows(_ facts: MenuFacts) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let active = facts.rows.filter { $0.lane == .active }
        let quiet = Provider.allCases.filter { provider in
            facts.rows.contains { $0.account.provider == provider && $0.lane == .quiet }
        }
        return VStack(alignment: .leading, spacing: 0) {
            if let adding = store.addingFor {
                AddingPanel(provider: adding)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
            lane("Needs a hop", facts.rows.filter { $0.lane == .needs }, facts: facts)
            lane("In use", Array(active.prefix(4)), facts: facts)
            if active.count > 4 {
                Button("\(active.count - 4) more in use") { AppWindow.show() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.muted)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            lane("Room", facts.rows.filter { $0.lane == .room }, facts: facts)
            if !quiet.isEmpty {
                Text("Quiet")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.subtle)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                Text(Self.quietLine(quiet.map(\.name)))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.subtle)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            if !facts.unset.isEmpty {
                Text("Not set up: \(facts.unset.map(\.name).joined(separator: ", ")).")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.top, quiet.isEmpty ? 8 : 0)
                    .padding(.bottom, 8)
            }
            addRow
        }
        .padding(.bottom, 4)
        .background(shape.fill(Color.white.opacity(0.03)))
        .overlay(shape.strokeBorder(Brand.border))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private static func quietLine(_ names: [String]) -> String {
        let list: String
        if names.count < 2 {
            list = names.joined()
        } else if names.count == 2 {
            list = "\(names[0]) and \(names[1])"
        } else {
            list = "\(names.dropLast().joined(separator: ", ")) and \(names[names.count - 1])"
        }
        return "\(list) \(names.count == 1 ? "has" : "have") no limit to read."
    }

    private func header(_ facts: MenuFacts) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tokens today")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.subtle)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Numbers.tokens(facts.tokens))
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Brand.text)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    if facts.cost > 0 {
                        Text(Numbers.usd(facts.cost))
                            .font(.system(size: 13))
                            .foregroundStyle(Brand.muted)
                    }
                }
            }
            if !facts.shares.isEmpty {
                shareBar(facts.shares)
                HStack(spacing: 14) {
                    ForEach(facts.shares.prefix(4)) { share in
                        HStack(spacing: 5) {
                            Circle().fill(share.color).frame(width: 6, height: 6)
                            Text(share.provider.shortName)
                                .foregroundStyle(Brand.text)
                            Text("\(share.percent)%")
                                .foregroundStyle(Brand.subtle)
                        }
                        .font(.system(size: 11.5))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(facts.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(facts.sub)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shareBar(_ shares: [MenuShare]) -> some View {
        GeometryReader { geo in
            let gaps = CGFloat(max(shares.count - 1, 0)) * 3
            let usable = max(0, geo.size.width - gaps)
            let widths = shareWidths(shares, usable: usable)
            HStack(spacing: 3) {
                ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                    Capsule()
                        .fill(share.color)
                        .frame(width: widths[index])
                }
            }
        }
        .frame(height: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Share of today's tokens")
    }

    /// A tiny share still gets a visible mark, and the marks still add up to the bar.
    private func shareWidths(_ shares: [MenuShare], usable: CGFloat) -> [CGFloat] {
        let raw = shares.map { max(CGFloat(4), usable * CGFloat($0.fraction)) }
        let sum = raw.reduce(0, +)
        guard sum > usable, sum > 0 else { return raw }
        let scale = usable / sum
        return raw.map { $0 * scale }
    }

    @ViewBuilder
    private func lane(_ title: String, _ rows: [MenuRow], facts: MenuFacts) -> some View {
        if !rows.isEmpty {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Brand.subtle)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 2)
            ForEach(rows) { row in
                MenuLoginRow(row: row, hop: row.account.id == facts.hopID, renaming: $renaming)
            }
        }
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { showAdd.toggle() } label: {
                HStack(spacing: 8) {
                    Icon("plus", size: 13)
                    Text("Add account")
                    Spacer()
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Brand.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle(quiet: true, radius: 8))
            .disabled(store.addingFor != nil || store.switching != nil)
            if showAdd {
                ForEach(Provider.switchable) { provider in
                    Button { showAdd = false; store.beginAdd(provider) } label: {
                        Text(provider.name)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Brand.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(RowButtonStyle(radius: 8))
                }
            }
        }
        .padding(.top, 4)
    }
}

/// A list that stays as short as its rows, and scrolls once it would run off the screen.
private struct FittingScroll<Content: View>: View {
    var maxHeight: CGFloat
    @ViewBuilder var content: () -> Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content()
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: MenuListHeightKey.self, value: proxy.size.height)
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : nil)
        .onPreferenceChange(MenuListHeightKey.self) { contentHeight = $0 }
    }
}

private struct MenuListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MenuLoginRow: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var tracker: UsageTracker
    let row: MenuRow
    let hop: Bool
    @Binding var renaming: UUID?

    var body: some View {
        let on = store.active[row.account.provider] == row.account.id
        Group {
            if renaming == row.account.id {
                face(on: on)
            } else {
                Button {
                    if !on { store.switchTo(row.account) }
                } label: {
                    face(on: on)
                }
                .buttonStyle(RowButtonStyle(radius: 8))
                .disabled(store.switching != nil && store.switching != row.account.id)
            }
        }
        .help(on ? "\(row.account.provider.name) is on \(row.account.email)" : "Switch \(row.account.provider.name) to \(row.account.email)")
        .accessibilityLabel(on ? "\(row.account.displayName), in use" : "Switch to \(row.account.displayName)")
        .contextMenu {
            Button("Rename…") { renaming = row.account.id }
            if !on {
                Divider()
                Button("Remove") { store.remove(row.account) }
            }
        }
    }

    private func face(on: Bool) -> some View {
        let account = row.account
        let snapshot = store.usage[account.id]
        let failed = snapshot?.error != nil && (snapshot?.windows.isEmpty ?? true)
        return HStack(spacing: 8) {
            MenuDot(lane: row.lane)
            EditableName(account: account, font: .system(size: 13, weight: .medium), renaming: $renaming)
                .foregroundStyle(row.lane == .needs ? Brand.warn : Brand.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: 156, alignment: .leading)
            Text(meta(snapshot))
                .font(.system(size: 12.5))
                .foregroundStyle(failed ? Brand.bad : Brand.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            if on, row.lane != .active {
                Text("In use")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.text)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .fixedSize()
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.1)))
            }
            if store.switching == account.id {
                ProgressView().controlSize(.small)
            } else if hop {
                Text("Hop")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.onPrimary)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .fixedSize()
                    .background(Capsule().fill(Brand.primary))
            } else if let used = row.used {
                Text("\(Int(used.rounded()))%")
                    .font(Brand.figure(12.5))
                    .foregroundStyle(row.lane == .needs ? Brand.warn : Brand.subtle)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func meta(_ snapshot: UsageSnapshot?) -> String {
        if snapshot?.error != nil, snapshot?.windows.isEmpty ?? true { return "Login expired" }
        var parts = [row.account.provider.shortName]
        if let plan = row.account.plan { parts.append(plan) }
        if let window = row.tightest {
            parts.append(window.label)
            if let eta = tracker.forecasts[AlertRules.forecastKey(row.account.id, window.label)], eta > Date(),
               window.resetsAt.map({ eta < $0 }) ?? true {
                parts.append("runs out \(eta.formatted(date: .omitted, time: .shortened))")
            }
        }
        return parts.joined(separator: " · ")
    }
}

private struct MenuShare: Identifiable {
    let provider: Provider
    let fraction: Double
    let percent: Int
    let color: Color
    var id: String { provider.rawValue }
}

private struct MenuRow: Identifiable {
    let account: Account
    let lane: MenuLane
    let used: Double?
    let tightest: UsageWindow?
    let today: Int
    var id: UUID { account.id }
}

@MainActor
private struct MenuFacts {
    let rows: [MenuRow]
    let unset: [Provider]
    let hopID: UUID?
    let title: String
    let sub: String
    let tokens: Int
    let cost: Double
    let shares: [MenuShare]

    static func make(store: AccountStore, tracker: UsageTracker, now: Date = Date()) -> MenuFacts {
        let rows = store.accounts.map { account -> MenuRow in
            let snapshot = store.usage[account.id]
            let windows = snapshot?.windows ?? []
            let tightest = windows.max { $0.usedPercent < $1.usedPercent }
            let active = store.active[account.provider] == account.id
            return MenuRow(
                account: account,
                lane: MenuStatus.lane(account, active: active, usage: store.usage, forecasts: tracker.forecasts, now: now),
                used: windows.map(\.usedPercent).max(),
                tightest: tightest,
                today: tracker.today[account.id]?.tokens.total ?? 0
            )
        }.sorted { ($0.used ?? -1) > ($1.used ?? -1) }

        let present = Set(store.accounts.map(\.provider))
        let unset = Provider.switchable.filter { !present.contains($0) }
        let hop = bestHop(store: store)
        let sentence = headline(rows: rows, hop: hop, empty: store.accounts.isEmpty)
        // The engine's total, so measured-only tools without accounts count too.
        let total = tracker.todayTotal
        return MenuFacts(
            rows: rows, unset: unset, hopID: hop?.to.id, title: sentence.0, sub: sentence.1,
            tokens: total.tokens.total, cost: total.cost, shares: shares(store: store, tracker: tracker)
        )
    }

    private static func shares(store: AccountStore, tracker: UsageTracker) -> [MenuShare] {
        // Per tool rather than per account, so measured-only tools show in the bar too.
        let totals = Provider.allCases.map { provider -> (Provider, Int) in
            (provider, tracker.todayByProvider[provider]?.tokens.total ?? 0)
        }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        let sum = totals.reduce(0) { $0 + $1.1 }
        guard sum > 0 else { return [] }
        return totals.map { provider, tokens in
            let fraction = Double(tokens) / Double(sum)
            let percent = max(fraction > 0 && fraction < 0.01 ? 1 : Int((fraction * 100).rounded()), fraction > 0 ? 1 : 0)
            let hex = DashboardUsage.toolColors[provider.rawValue] ?? "#6E7A52"
            return MenuShare(provider: provider, fraction: fraction, percent: percent, color: Color(hex: hex))
        }
    }

    private static func bestHop(store: AccountStore) -> (tool: Provider, from: Account, to: Account, gap: Double)? {
        var best: (tool: Provider, from: Account, to: Account, gap: Double)?
        for tool in Provider.allCases {
            let accounts = store.accounts(for: tool)
            guard let activeID = store.active[tool], let current = accounts.first(where: { $0.id == activeID }),
                  let currentUsed = used(current, store: store) else { continue }
            let pick = accounts
                .filter { $0.id != current.id && store.usage[$0.id]?.error == nil && !(store.usage[$0.id]?.windows.isEmpty ?? true) }
                .min { (used($0, store: store) ?? 101) < (used($1, store: store) ?? 101) }
            guard let pick, let pickUsed = used(pick, store: store), pickUsed + 15 < currentUsed else { continue }
            let gap = currentUsed - pickUsed
            if best == nil || gap > best!.gap { best = (tool, current, pick, gap) }
        }
        return best
    }

    private static func used(_ account: Account, store: AccountStore) -> Double? {
        store.usage[account.id]?.windows.map(\.usedPercent).max()
    }

    private static func headline(rows: [MenuRow], hop: (tool: Provider, from: Account, to: Account, gap: Double)?, empty: Bool) -> (String, String) {
        if let hop {
            let fromUsed = Int((usedPercent(hop.from, rows: rows) ?? 0).rounded())
            let toUsed = Int((usedPercent(hop.to, rows: rows) ?? 0).rounded())
            return (
                "\(hop.tool.shortName) still has room.",
                "\(Self.brief(hop.from)) is in use at \(fromUsed)%. \(Self.brief(hop.to)) is at \(toUsed)%."
            )
        }
        if let wall = rows.first(where: { $0.lane == .needs }) {
            let n = Int((wall.used ?? 0).rounded())
            return ("\(wall.account.provider.shortName) is at \(n)%.", "There is no other login to hop to.")
        }
        if empty { return ("Add a login.", "No saved accounts yet. Sign in once and Keyhop keeps the login.") }
        return ("Every login in use has room.", "Nothing is close to a limit.")
    }

    private static func usedPercent(_ account: Account, rows: [MenuRow]) -> Double? {
        rows.first { $0.account.id == account.id }?.used
    }

    /// Two logins often share a name. The domain is what tells them apart.
    private static func brief(_ account: Account) -> String {
        let name = account.displayName
        guard let at = name.lastIndex(of: "@") else { return name }
        let domain = name[name.index(after: at)...]
        return domain.isEmpty ? name : String(domain)
    }
}

/// The same reading as the window: a login at 85%, one that runs out before it resets, or an error.
private enum MenuLane {
    case needs, active, room, quiet
}

private enum MenuStatus {
    static func lane(_ account: Account, active: Bool, usage: [UUID: UsageSnapshot], forecasts: [String: Date], now: Date = Date()) -> MenuLane {
        let windows = usage[account.id]?.windows ?? []
        if usage[account.id]?.error != nil, windows.isEmpty { return .needs }
        if windows.isEmpty { return .quiet }
        if windows.contains(where: { $0.usedPercent >= 85 }) { return .needs }
        if windows.contains(where: { runsOut($0, account: account, forecasts: forecasts, now: now) }) { return .needs }
        return active ? .active : .room
    }

    private static func runsOut(_ window: UsageWindow, account: Account, forecasts: [String: Date], now: Date) -> Bool {
        guard let eta = forecasts[AlertRules.forecastKey(account.id, window.label)], eta > now else { return false }
        if let reset = window.resetsAt, eta >= reset { return false }
        return true
    }
}

private struct MenuDot: View {
    let lane: MenuLane

    var body: some View {
        Circle()
            .fill(fill)
            .overlay {
                if let stroke {
                    Circle().strokeBorder(stroke, lineWidth: 1.5)
                }
            }
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }

    private var fill: Color {
        switch lane {
        case .needs: Brand.warn
        case .room: Brand.good
        case .active, .quiet: .clear
        }
    }

    private var stroke: Color? {
        switch lane {
        case .active: Brand.info
        case .quiet: Brand.subtle
        case .needs, .room: nil
        }
    }
}

private struct AddingPanel: View {
    @EnvironmentObject private var store: AccountStore
    let provider: Provider

    var body: some View {
        VStack(spacing: 10) {
            PixelMark(animated: true)
                .frame(width: 34, height: 34)
                .padding(.bottom, 4)
            Text("Waiting for a new \(provider.name) login")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.text)
            Text(LocalizedStringKey(provider.signInHint))
                .font(.system(size: 12))
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Cancel") { store.cancelAdd() }
                .buttonStyle(AppButtonStyle(kind: .secondary, size: .small))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .card()
    }
}
private struct EditableName: View {
    @EnvironmentObject private var store: AccountStore
    let account: Account
    let font: Font
    @Binding var renaming: UUID?
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if renaming == account.id {
            TextField(account.email, text: $draft)
                .textFieldStyle(.plain)
                .font(font)
                .focused($focused)
                .onAppear {
                    draft = account.label ?? ""
                    focused = true
                }
                .onSubmit(commit)
                .onExitCommand { renaming = nil }
        } else {
            Text(account.displayName)
                .font(font)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func commit() {
        store.rename(account, to: draft)
        renaming = nil
    }
}

// MARK: Notice and footer

private struct NoticeLine: View {
    @EnvironmentObject private var store: AccountStore
    let text: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Text(LocalizedStringKey(text))
            .font(.system(size: 12))
            .foregroundStyle(Brand.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(shape.fill(Brand.raised))
            .overlay(shape.strokeBorder(Brand.borderStrong))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .onTapGesture { store.notice = nil }
            .task(id: text) {
                try? await Task.sleep(for: .seconds(9))
                if store.notice == text { store.notice = nil }
            }
    }
}

private struct MenuFooter: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var tracker: UsageTracker
    @ObservedObject private var updater = Updater.shared
    @AppStorage("autoRefresh") private var autoRefresh = true
    @AppStorage("checkForUpdates") private var checkForUpdates = true
    @AppStorage("autoInstallUpdates") private var autoInstallUpdates = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(\.staticSnapshot) private var staticSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Button("Open Keyhop") { AppWindow.show() }
                .buttonStyle(AppButtonStyle(kind: .primary, size: .small))
                .help("Open Keyhop's window")

            Spacer(minLength: 8)

            TimelineView(.periodic(from: .now, by: store.isRefreshing || tracker.isUpdating ? 0.25 : 30)) { context in
                Text(updatedText(context.date))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Brand.subtle)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel(updatedAccessibilityText(context.date))
            }

            Button { store.refresh() } label: {
                TimelineView(.animation(paused: !store.isRefreshing)) { context in
                    Icon("refresh", size: 13)
                        .rotationEffect(.degrees(store.isRefreshing ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360 : 0))
                }
            }
            .buttonStyle(AppButtonStyle(kind: .ghost, size: .small))
            .help("Refresh usage")
            .accessibilityLabel(store.isRefreshing ? "Refreshing" : "Refresh usage")

            if staticSnapshot {
                Icon("more", size: 14)
                    .foregroundStyle(Brand.muted)
                    .frame(width: 28, height: 28)
            } else {
                moreMenu
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Brand.sidebar)
        .overlay(alignment: .top) {
            if store.isRefreshing || tracker.isUpdating {
                WorkMeter(box: store.progress)
            } else {
                RowDivider()
            }
        }
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                store.notice = "Open at login needs Keyhop in Applications."
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private var moreMenu: some View {
            Menu {
                Text("Keyhop \(Updater.currentVersion)")
                Button("Open Keyhop") { AppWindow.show() }
                Button("Check for Updates…") { Task { await updater.check(userInitiated: true) } }
                Divider()
                Toggle("Check usage every 5 minutes", isOn: $autoRefresh)
                Toggle("Check for updates automatically", isOn: $checkForUpdates)
                Toggle("Install updates automatically", isOn: $autoInstallUpdates)
                    .disabled(!checkForUpdates)
                Toggle("Open at login", isOn: $launchAtLogin)
                Divider()
                Button("Quit Keyhop") { NSApp.terminate(nil) }
            } label: {
                Icon("more", size: 14)
                    .foregroundStyle(Brand.muted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28, height: 28)
            .help("More")
            .accessibilityLabel("More")
    }

    private func updatedText(_ now: Date) -> String {
        if let step = store.progress.value { return step.brief }
        if store.isRefreshing { return "Refreshing limits…" }
        if tracker.isUpdating { return "Reading usage…" }
        guard let last = store.lastRefresh else { return "Not refreshed" }
        let minutes = Int(now.timeIntervalSince(last) / 60)
        return minutes < 1 ? "Updated now" : "Updated \(minutes)m ago"
    }

    private func updatedAccessibilityText(_ now: Date) -> String {
        if store.isRefreshing { return "Refreshing account limits" }
        if tracker.isUpdating { return "Reading local usage" }
        guard let last = store.lastRefresh else { return "Limits have not been refreshed" }
        return "Limits updated \(last.formatted(.relative(presentation: .named)))"
    }
}
#endif


#if os(macOS)
/// The footer's top edge doubles as a progress bar while Keyhop reads: filled as far as the step
/// has got, or a short segment moving along it while the total isn't known.
private struct WorkMeter: View {
    let box: ProgressBox
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Rectangle().fill(Brand.border)
                    if let fraction = box.value?.fraction {
                        Capsule().fill(Brand.text)
                            .frame(width: max(2, width * fraction))
                            .animation(.easeOut(duration: 0.3), value: fraction)
                    } else {
                        let phase = reduceMotion ? 0.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.3) / 1.3
                        Capsule().fill(Brand.text)
                            .frame(width: width * 0.28)
                            .offset(x: -width * 0.28 + phase * width * 1.28)
                    }
                }
                .clipped()
            }
            .frame(height: 2)
        }
        .accessibilityHidden(true)
    }
}
#endif
