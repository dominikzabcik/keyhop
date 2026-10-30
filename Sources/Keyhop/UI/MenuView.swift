#if os(macOS)
import ServiceManagement
import SwiftUI

/// The menu bar panel, built from the notch's pieces in the notch's black: what needs you in a
/// sentence with the one action that helps, a group of limit rows per tool, and the notch's foot.
/// Refresh and More sit by the read time. A group opens that tool's logins, to switch, rename or
/// add one. It opens on the last reading at once; a read runs quietly behind.
struct MenuView: View {
    static let width: CGFloat = 420

    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var tracker: UsageTracker
    @State private var opened: Provider?
    @State private var renaming: UUID?

    init(opened: Provider? = nil) {
        _opened = State(initialValue: opened)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(facts: MenuFacts.make(store: store, tracker: tracker, now: context.date), now: context.date)
        }
        .frame(width: Self.width)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    private func content(facts: MenuFacts, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuHead(facts: facts, now: now)

            if let adding = store.addingFor {
                AddingPanel(provider: adding)
                    .padding([.horizontal, .top], 12)
            }

            if facts.groups.isEmpty {
                EmptyLine()
            } else {
                MenuGroups(facts: facts, opened: $opened, renaming: $renaming)
            }

            if let notice = store.notice {
                NoticeLine(text: notice)
            }

            UpdateLine()

            RowDivider()
            ReadoutFoot(today: facts.today, close: { MenuPanel.shared.close() })
                .frame(minHeight: 44)
                .padding(.horizontal, 20)
        }
    }
}

// MARK: Head

/// How many logins and when they were read, then in a sentence what needs you, and the one action
/// that helps: the hop, or else the remedy. Only what the tools report.
private struct MenuHead: View {
    @EnvironmentObject private var store: AccountStore
    let facts: MenuFacts
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(Brand.sans(11.5, weight: .medium))
                    .foregroundStyle(Brand.subtle)
                    .lineLimit(1)
                Spacer(minLength: 8)
                ReadTime(readAt: store.lastRefresh, now: now)
                MenuControls()
            }
            Button {
                AppWindow.show(section: "home")
            } label: {
                Text(facts.title)
                    .font(Brand.sans(16, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .buttonStyle(.plain)
            .help("Open Keyhop")
            Text(facts.sub)
                .font(Brand.sans(12))
                .foregroundStyle(Brand.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let hop = facts.hop {
                HopButton(hop: hop).padding(.top, 9)
            } else if let warning = facts.warning {
                WarningButton(warning: warning).padding(.top, 9)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 13)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { RowDivider() }
        .accessibilityElement(children: .contain)
    }

    private var label: String {
        let logins = store.accounts.count
        return logins == 1 ? "1 login" : "\(logins) logins"
    }
}

/// The one hop that helps most, named for where it goes.
private struct HopButton: View {
    @EnvironmentObject private var store: AccountStore
    let hop: MenuHop

    var body: some View {
        Button {
            store.switchTo(hop.to)
        } label: {
            HStack(spacing: 7) {
                if store.switching == hop.to.id {
                    ProgressView().controlSize(.mini)
                }
                Text("Hop to \(hop.to.displayName)")
                    .truncationMode(.middle)
            }
        }
        .buttonStyle(AppButtonStyle(kind: .primary, size: .small))
        .disabled(store.switching != nil)
        .help("Hop \(hop.tool.name) to \(hop.to.email)")
    }
}

/// The remedy for what the sentence says, when no hop helps.
private struct WarningButton: View {
    @EnvironmentObject private var store: AccountStore
    let warning: MenuWarning

    var body: some View {
        Button {
            switch warning.action {
            case .add: store.beginAdd(warning.account.provider)
            case .open: AppWindow.show(section: "limits")
            }
        } label: {
            Text(warning.action == .add ? "Add a \(warning.account.provider.shortName) login" : "Open Limits")
        }
        .buttonStyle(AppButtonStyle(kind: .secondary, size: .small))
        .disabled(warning.action == .add && store.addingFor != nil)
    }
}

// MARK: Groups

/// The notch's rows, one group per tool split by hairlines. Pressing a group opens its logins.
private struct MenuGroups: View {
    let facts: MenuFacts
    @Binding var opened: Provider?
    @Binding var renaming: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(facts.groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    RowDivider().padding(.horizontal, 20).padding(.vertical, 8)
                }
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { opened = opened == group.provider ? nil : group.provider }
                } label: {
                    LimitRows(group: group)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowButtonStyle(radius: 8))
                .padding(.horizontal, 12)
                .help("\(group.provider.name) reads \(group.login.displayName). Show its logins")
                .accessibilityHint("Shows its logins")
                if opened == group.provider {
                    MenuLogins(provider: group.provider, facts: facts, renaming: $renaming)
                        .transition(.opacity)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

/// The opened group's logins, under its name: press one to switch to it; rename or remove from
/// its context menu. Past five logins the list scrolls, so the panel always fits under the menu bar.
private struct MenuLogins: View {
    @EnvironmentObject private var store: AccountStore
    let provider: Provider
    let facts: MenuFacts
    @Binding var renaming: UUID?

    private static let shownRows = 5
    private static let rowHeight: CGFloat = 36

    var body: some View {
        let rows = facts.rows.filter { $0.account.provider == provider }
        VStack(alignment: .leading, spacing: 0) {
            if rows.count > Self.shownRows {
                ScrollView(.vertical) { list(rows) }
                    .scrollIndicators(.automatic)
                    .frame(height: CGFloat(Self.shownRows) * Self.rowHeight + Self.rowHeight / 2)
            } else {
                list(rows)
            }
            Button { store.beginAdd(provider) } label: {
                HStack(spacing: 10) {
                    Icon("plus", size: 12)
                        .frame(width: 8)
                    Text("Add a \(provider.shortName) login")
                    Spacer()
                }
                .font(Brand.sans(12.5, weight: .medium))
                .padding(.horizontal, 8)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle(quiet: true, radius: 8))
            .disabled(store.addingFor != nil || store.switching != nil || !Provider.switchable.contains(provider))
        }
        .padding(.leading, 32)
        .padding(.trailing, 12)
        .padding(.bottom, 4)
    }

    private func list(_ rows: [MenuRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                MenuLoginRow(row: row, hop: row.account.id == facts.hop?.to.id, renaming: $renaming)
            }
        }
    }
}

private struct MenuLoginRow: View {
    @EnvironmentObject private var store: AccountStore
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
        .help(on ? "\(row.account.provider.name) is on \(row.account.email)"
              : row.signedOut ? "Switch to \(row.account.email) and sign in to \(row.account.provider.name) again"
              : "Switch \(row.account.provider.name) to \(row.account.email)")
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
        return HStack(spacing: 10) {
            Circle()
                .fill(on ? Brand.text : .clear)
                .overlay(Circle().strokeBorder(on ? .clear : Brand.subtle, lineWidth: 1.5))
                .frame(width: 7, height: 7)
                .frame(width: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                EditableName(account: account, font: Brand.sans(12.5, weight: .medium), renaming: $renaming)
                    .foregroundStyle(Brand.text)
                Text(meta)
                    .font(Brand.sans(11))
                    .foregroundStyle(row.signedOut ? Brand.bad : Brand.subtle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            if store.switching == account.id {
                ProgressView().controlSize(.small)
            } else if hop {
                Text("Hop")
                    .font(Brand.sans(11.5, weight: .semibold))
                    .foregroundStyle(Brand.onPrimary)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .fixedSize()
                    .background(Capsule().fill(Brand.primary))
            } else if row.signedOut {
                Text("Sign in")
                    .font(Brand.sans(12, weight: .medium))
                    .foregroundStyle(Brand.text)
                    .fixedSize()
            } else if let left = row.left {
                Text("\(left)% left")
                    .font(Brand.mono(11.5, weight: .medium))
                    .foregroundStyle(LimitTone(left: left) == .out ? Brand.bad : Brand.muted)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(minHeight: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The plan and the tightest window, as the window's Limits says it: signed out only when the
    /// tool turned the login down, and a reading that failed shows how old the last one is.
    private var meta: String {
        if row.signedOut { return "Signed out" }
        var parts: [String] = []
        if let plan = row.account.plan { parts.append(plan) }
        if let window = row.tightest { parts.append(window.label.lowercased()) }
        if row.account.isKeptForLast { parts.append("kept for last") }
        if row.readFailed || row.waiting, let at = row.readAt { parts.append("last read \(MenuFacts.ago(at))") }
        if row.waiting, row.left == nil { parts.append("waits for open sessions") }
        return parts.isEmpty ? row.account.provider.name : parts.joined(separator: " · ")
    }
}

/// Before the first login: what to do, said once.
private struct EmptyLine: View {
    var body: some View {
        Text("No limits to read yet. Add a login from More, and Keyhop keeps it.")
            .font(Brand.sans(12.5))
            .foregroundStyle(Brand.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
    }
}

// MARK: Facts

private struct MenuHop {
    let tool: Provider
    let from: Account
    let to: Account
    let fromLeft: Int
    let toLeft: Int
}

private struct MenuWarning {
    enum Action: Equatable {
        case add, open
    }

    let account: Account
    let action: Action
}

private struct MenuRow: Identifiable {
    let account: Account
    let active: Bool
    /// What the tightest window has left, as the tools report it; back to 100 once its reset has
    /// passed. Nil when signed out or nothing was read.
    let left: Int?
    let tightest: UsageWindow?
    let signedOut: Bool
    /// The last reading failed (the network, a busy server), so what shows is the one before.
    let readFailed: Bool
    /// Keyhop held off reading it, so what shows is the last reading.
    let waiting: Bool
    let readAt: Date?
    var id: UUID { account.id }
    /// The same reading as the window: a login with 15% or less left, or one signed out, needs you.
    var needsYou: Bool { signedOut || LimitTone(left: left ?? 100) == .out }
}

@MainActor
private struct MenuFacts {
    let rows: [MenuRow]
    let groups: [LimitGroup]
    let hop: MenuHop?
    let warning: MenuWarning?
    let title: String
    let sub: String
    let today: TodayLine.Today?

    static func make(store: AccountStore, tracker: UsageTracker, now: Date = Date()) -> MenuFacts {
        let rows = store.accounts.map { account -> MenuRow in
            let snapshot = store.usage[account.id]
            let signedOut = snapshot?.signedOut == true
            let windows = signedOut ? [] : (snapshot?.windows ?? [])
            let tightest = windows.min { SmartHop.room($0, now) < SmartHop.room($1, now) }
            return MenuRow(account: account, active: store.active[account.provider] == account.id,
                           left: tightest.map { Int(SmartHop.room($0, now).rounded()) }, tightest: tightest,
                           signedOut: signedOut, readFailed: snapshot?.error != nil && !signedOut,
                           waiting: snapshot?.waiting != nil, readAt: snapshot?.fetchedAt)
        }
        // In use first, then the most room; signed-out logins last.
        .sorted { a, b in
            if a.active != b.active { return a.active }
            if a.signedOut != b.signedOut { return !a.signedOut }
            return (a.left ?? -1) > (b.left ?? -1)
        }

        let groups = LimitGroup.make(store: store, now: now)
        let hop = bestHop(rows: rows, store: store, tracker: tracker, now: now)
        let sentence = headline(rows: rows, groups: groups, hop: hop, empty: store.accounts.isEmpty)
        return MenuFacts(
            rows: rows, groups: groups, hop: hop,
            warning: hop == nil ? warning(rows: rows) : nil,
            title: sentence.0, sub: sentence.1, today: TodayLine.Today(tracker: tracker)
        )
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours)h ago" : "\(hours / 24)d ago"
    }

    /// Only the logins in use: one that is signed out, or nearly out with no login to hop to.
    /// The headline says what is wrong; the warning carries only the remedy.
    private static func warning(rows: [MenuRow]) -> MenuWarning? {
        guard let row = rows.first(where: { $0.active && $0.needsYou }) else { return nil }
        let account = row.account
        if row.signedOut { return MenuWarning(account: account, action: .open) }
        let others = rows.filter { $0.account.provider == account.provider && $0.account.id != account.id }
        if others.isEmpty, Provider.switchable.contains(account.provider) {
            return MenuWarning(account: account, action: .add)
        }
        return MenuWarning(account: account, action: .open)
    }

    /// The window's rule: Smart Hop's pick for a tool, when it has room worth a hop and clearly
    /// more than the login in use. Of several tools, the one with the biggest gain.
    private static func bestHop(rows: [MenuRow], store: AccountStore, tracker: UsageTracker, now: Date) -> MenuHop? {
        var best: (hop: MenuHop, gain: Int)?
        for tool in Provider.switchable {
            guard let current = rows.first(where: { $0.active && $0.account.provider == tool }),
                  let pick = SmartHop.recommendation(
                      for: tool, accounts: store.accounts, active: store.active, usage: store.usage,
                      forecasts: tracker.forecasts, budgets: tracker.budgets, budgetSpend: tracker.budgetSpend,
                      excluding: [current.account.id], now: now),
                  !pick.active, pick.room >= SmartHop.usefulRoom,
                  let to = store.accounts.first(where: { $0.id == pick.account }) else { continue }
            let here = current.signedOut ? 0 : current.left ?? 100
            let room = Int(pick.room.rounded())
            guard room > here + 10 else { continue }
            if best == nil || room - here > best!.gain {
                best = (MenuHop(tool: tool, from: current.account, to: to, fromLeft: here, toLeft: room), room - here)
            }
        }
        return best?.hop
    }

    /// The notification's words: "nearly out" at 15% or less, "running low" at 40% or less.
    private static func headline(rows: [MenuRow], groups: [LimitGroup], hop: MenuHop?, empty: Bool) -> (String, String) {
        if empty { return ("Add a login.", "No saved logins yet. Sign in once and Keyhop keeps the login.") }
        if let hop {
            let state = LimitTone(left: hop.fromLeft) == .out ? "is nearly out" : "is running low"
            return ("\(hop.tool.shortName) \(state).",
                    "\(brief(hop.from)) has \(hop.fromLeft)% left. \(brief(hop.to)) has \(hop.toLeft)%.")
        }
        if let wall = rows.first(where: { $0.active && $0.needsYou }) {
            let tool = wall.account.provider.shortName
            if wall.signedOut { return ("\(tool) is signed out.", "Sign in to \(wall.account.provider.name) again to keep going.") }
            let others = rows.filter { $0.account.provider == wall.account.provider && $0.account.id != wall.account.id }
            let why = others.isEmpty ? "There is no other login to hop to." : "No other \(tool) login has room for a hop."
            return ("\(tool) is nearly out.", "\(brief(wall.account)) has \(wall.left ?? 0)% left. \(why)")
        }
        if let group = groups.first(where: { !$0.lines.isEmpty }), let line = group.lines.first {
            let resets = line.reset.isEmpty ? "" : ", back in \(line.reset)"
            return ("Every login in use has room.",
                    "The tightest is \(group.provider.shortName)'s \(line.window) window, \(line.left)% left\(resets).")
        }
        return ("Nothing read yet.", "Keyhop reads the limits in the background.")
    }

    /// Two logins often share a name. The domain is what tells them apart.
    private static func brief(_ account: Account) -> String {
        let name = account.displayName
        guard let at = name.lastIndex(of: "@") else { return name }
        let domain = name[name.index(after: at)...]
        return domain.isEmpty ? name : String(domain)
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
                .font(Brand.sans(14, weight: .semibold))
                .foregroundStyle(Brand.text)
            Text(LocalizedStringKey(provider.signInHint))
                .font(Brand.sans(12))
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
            .font(Brand.sans(12))
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

/// Refresh, as a quiet icon that turns while the limits are read, and More, which holds the
/// settings, adding a login and Quit.
private struct MenuControls: View {
    @EnvironmentObject private var store: AccountStore
    @ObservedObject private var updater = Updater.shared
    @AppStorage("autoRefresh") private var autoRefresh = true
    @AppStorage("autoHop") private var autoHop = false
    @AppStorage("notchCompanion") private var notchCompanion = false
    @AppStorage("checkForUpdates") private var checkForUpdates = true
    @AppStorage("autoInstallUpdates") private var autoInstallUpdates = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(\.staticSnapshot) private var staticSnapshot

    var body: some View {
        HStack(spacing: 2) {
            Button { store.refresh() } label: {
                Group {
                    // Only a read of the limits shows here, and only while one runs.
                    if store.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Icon("refresh", size: 12)
                    }
                }
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle(quiet: true, radius: 6))
            .keyboardShortcut("r")
            .help(store.isRefreshing ? "Reading the limits" : "Refresh the limits (⌘R)")
            .accessibilityLabel(store.isRefreshing ? "Reading the limits" : "Refresh the limits")

            if staticSnapshot {
                Icon("more", size: 12).frame(width: 24, height: 22)
            } else {
                moreMenu
            }
        }
        .foregroundStyle(Brand.muted)
        .padding(.leading, 4)
        .onChange(of: notchCompanion) { _, enabled in
            NotchWindow.shared.apply(enabled)
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
            Text("Keyhop \(Updater.currentVersion)\(AppVersion.isPrerelease ? " · Beta" : "")")
            Button("Open Keyhop") { AppWindow.show() }
            Menu("Add Account") {
                ForEach(Provider.switchable) { provider in
                    Button(provider.name) { store.beginAdd(provider) }
                }
            }
            .disabled(store.addingFor != nil || store.switching != nil)
            Button("Check for Updates…") { Task { await updater.check(userInitiated: true) } }
            Picker("Update Channel", selection: Binding(get: { updater.channel }, set: { updater.choose($0) })) {
                ForEach(UpdateChannel.allCases, id: \.self) { channel in
                    Text(channel.title).tag(channel)
                }
            }
            Divider()
            Toggle("Check usage every 5 minutes", isOn: $autoRefresh)
            Toggle("Hop before a limit automatically", isOn: $autoHop)
                .disabled(!autoRefresh)
            if NotchWindow.hasNotchScreen {
                Toggle("Show under the notch", isOn: $notchCompanion)
            }
            Toggle("Check for updates automatically", isOn: $checkForUpdates)
            Toggle("Install updates automatically", isOn: $autoInstallUpdates)
                .disabled(!checkForUpdates)
            Toggle("Open at login", isOn: $launchAtLogin)
            Divider()
            Button("Quit Keyhop") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Icon("more", size: 12)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 24, height: 22)
        .help("Settings, adding a login, and Quit")
        .accessibilityLabel("More")
    }
}
#endif

