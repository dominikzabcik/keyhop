#if os(macOS)
import ServiceManagement
import SwiftUI

/// The menu bar menu, in the dashboard's design: tool tabs, the account in use as a card, the
/// others as a list, and a footer that opens Keyhop's window.
struct MenuView: View {
    @EnvironmentObject private var store: AccountStore
    @AppStorage("menuTool") private var tool: Provider = .claude
    @State private var renaming: UUID?
    @Namespace private var tabs

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToolTabs(selection: $tool, namespace: tabs)
                .padding(12)

            ToolPanel(provider: tool, renaming: $renaming)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

            if let notice = store.notice {
                NoticeLine(text: notice)
            }

            UpdateLine()

            MenuFooter()
        }
        .frame(width: 340)
        .background(Brand.background)
        .environment(\.colorScheme, .dark)
        .onAppear {
            if let focus = store.focusProvider {
                tool = focus
            } else if store.accounts(for: tool).isEmpty,
                      let used = Provider.allCases.first(where: { !store.accounts(for: $0).isEmpty }) {
                // Open on a tool you actually use.
                tool = used
            }
        }
    }
}

// MARK: Tabs

private struct ToolTabs: View {
    @Binding var selection: Provider
    let namespace: Namespace.ID

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 2) {
            ForEach(Provider.allCases) { provider in
                ToolTab(provider: provider, selected: provider == selection, namespace: namespace) {
                    withAnimation(.snappy(duration: 0.24)) { selection = provider }
                }
            }
        }
        .padding(3)
        .background(shape.fill(Brand.raised))
        .overlay(shape.strokeBorder(Brand.border))
    }
}

private struct ToolTab: View {
    let provider: Provider
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let lit = selected || hovering
        Button(action: action) {
            HStack(spacing: 6) {
                ProviderMark(provider: provider, tint: lit ? Brand.text : Brand.muted)
                    .frame(width: 12, height: 12)
                Text(provider.shortName)
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(lit ? Brand.text : Brand.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Brand.selected)
                        .matchedGeometryEffect(id: "tab", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(provider.name)
        .accessibilityLabel(provider.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Panel

private struct ToolPanel: View {
    @EnvironmentObject private var store: AccountStore
    let provider: Provider
    @Binding var renaming: UUID?

    var body: some View {
        let accounts = store.accounts(for: provider)
        let inUse = store.active[provider].flatMap { id in accounts.first { $0.id == id } }
        let others = accounts
            .filter { $0.id != inUse?.id }
            .sorted { (room($0) ?? -1) > (room($1) ?? -1) }
        // Only point at an alternative when the account in use is actually getting tight.
        let best: UUID? = {
            guard let inUse, let inUseRoom = room(inUse), inUseRoom < 30,
                  let candidate = others.first, let candidateRoom = room(candidate), candidateRoom >= 20 else { return nil }
            return candidate.id
        }()

        VStack(spacing: 10) {
            if store.addingFor == provider {
                AddingPanel(provider: provider)
            } else if accounts.isEmpty {
                EmptyPanel(provider: provider)
            } else {
                if let inUse {
                    InUseCard(account: inUse, renaming: $renaming)
                } else {
                    SignedOutCard(provider: provider)
                }
                VStack(spacing: 0) {
                    ForEach(others) { account in
                        AlternativeRow(account: account, best: account.id == best, renaming: $renaming)
                        RowDivider()
                    }
                    AddRow(provider: provider)
                }
                .card()
            }
        }
    }

    /// Room left on the tightest limit, in percent.
    private func room(_ account: Account) -> Double? {
        store.usage[account.id]?.windows.map { 100 - $0.usedPercent }.min()
    }
}

private struct InUseCard: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var tracker: UsageTracker
    let account: Account
    @Binding var renaming: UUID?

    var body: some View {
        let snapshot = store.usage[account.id]
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    EditableName(account: account, font: .system(size: 14, weight: .semibold), renaming: $renaming)
                        .foregroundStyle(Brand.text)
                    Spacer(minLength: 8)
                    Badge("In use", live: true)
                }
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.subtle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(14)

            RowDivider()

            VStack(alignment: .leading, spacing: 12) {
                if let snapshot, !snapshot.windows.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                        ForEach(snapshot.windows) { window in
                            LimitCell(window: window, runsOut: tracker.forecasts[UsageTracker.forecastKey(account.id, window.label)])
                        }
                    }
                    if let error = snapshot.error {
                        Text("\(error) Showing the last reading.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Brand.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(snapshot?.error ?? (snapshot?.fetchedAt == nil ? "Reading limits…" : "This plan reports no limits."))
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)

            if let spend = tracker.today[account.id], spend.requests > 0 {
                RowDivider()
                SpendLine(account: account, spend: spend)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .card()
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename…") { renaming = account.id }
            Button("Refresh usage") { store.refresh() }
        }
    }

    private var detail: String? {
        let parts = [account.label != nil ? account.email : nil, account.plan].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct LimitCell: View {
    let window: UsageWindow
    let runsOut: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let outSoon = runsOut.map { $0 > context.date } ?? false
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(window.label)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Brand.muted)
                    Spacer(minLength: 4)
                    Text("\(Int(window.usedPercent.rounded()))%")
                        .font(Brand.mono(12, weight: .medium))
                        .foregroundStyle(Brand.text)
                }
                .padding(.bottom, 7)
                LimitBar(fraction: window.usedPercent / 100, pace: window.pace(at: context.date))
                Text(outSoon ? "Runs out \(runsOut!.formatted(date: .omitted, time: .shortened))" : resetCaption(context.date))
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(outSoon ? Brand.warn : Brand.subtle)
                    .lineLimit(1)
                    .padding(.top, 6)
            }
            .help(helpText(context.date))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(window.label) limit")
            .accessibilityValue("\(Int(window.usedPercent.rounded())) percent used, "
                + (outSoon ? "runs out around \(runsOut!.formatted(date: .omitted, time: .shortened))" : resetCaption(context.date)))
        }
    }

    private func resetCaption(_ now: Date) -> String {
        window.resetsAt == nil ? " " : "Resets in \(window.resetText(at: now))"
    }

    private func helpText(_ now: Date) -> String {
        var parts = ["\(Int(window.usedPercent.rounded()))% of the \(window.label.lowercased()) limit used"]
        if let runsOut, runsOut > now { parts.append("at the recent rate it runs out around \(runsOut.formatted(date: .omitted, time: .shortened))") }
        if let pace = window.pace(at: now) { parts.append("the tick marks an even pace (\(Int((pace * 100).rounded()))%)") }
        return parts.joined(separator: ", ")
    }
}

private struct SpendLine: View {
    @EnvironmentObject private var tracker: UsageTracker
    let account: Account
    let spend: Totals

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            (Text("Today  ").foregroundStyle(Brand.muted)
                + Text(Numbers.tokens(spend.tokens.total)).font(Brand.mono(11.5)).foregroundStyle(Brand.text)
                + Text(" tokens · ").foregroundStyle(Brand.muted)
                + Text(Numbers.usd(spend.cost)).font(Brand.mono(11.5)).foregroundStyle(Brand.text)
                + Text(" at API prices").foregroundStyle(Brand.subtle))
                .lineLimit(1)
            if let budget = tracker.budget(for: Budget.scope(for: account.id)), budget.amount > 0 {
                let share = (tracker.budgetSpend[budget.scope] ?? 0) / budget.amount
                Text("\(Int((share * 100).rounded()))% of the \(budget.period.adjective) budget of \(Numbers.usd(budget.amount))")
                    .foregroundStyle(share >= 0.8 ? Brand.warn : Brand.subtle)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11.5))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SignedOutCard: View {
    let provider: Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Signed out of \(provider.name)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.text)
            Text("Pick an account below to sign back in.")
                .font(.system(size: 12))
                .foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }
}

private struct AlternativeRow: View {
    @EnvironmentObject private var store: AccountStore
    let account: Account
    let best: Bool
    @Binding var renaming: UUID?

    var body: some View {
        let snapshot = store.usage[account.id]
        let limits = snapshot?.windows ?? []
        let room = limits.map { 100 - $0.usedPercent }.min()
        let problem = snapshot?.error != nil && limits.isEmpty

        Button {
            if renaming != account.id { store.switchTo(account) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    EditableName(account: account, font: .system(size: 13, weight: .medium), renaming: $renaming)
                        .foregroundStyle(Brand.text)
                    subtitle(snapshot)
                        .font(.system(size: 12))
                        .lineLimit(problem ? 2 : 1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if store.switching == account.id {
                    ProgressView().controlSize(.small)
                } else if let room, snapshot?.error == nil {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(room.rounded()))%")
                            .font(Brand.mono(13, weight: .medium))
                            .foregroundStyle(Brand.text)
                        Text("left")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Brand.subtle)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .disabled(store.switching != nil && store.switching != account.id)
        .help("Switch \(account.provider.name) to \(account.email)")
        .accessibilityLabel("Switch to \(account.displayName)")
        .accessibilityValue(room.map { "\(Int($0.rounded())) percent left" } ?? subtitleWords(snapshot))
        .contextMenu {
            Button("Rename…") { renaming = account.id }
            Divider()
            Button("Remove") { store.remove(account) }
        }
    }

    private func detailWords() -> String? {
        if account.label != nil { return account.email }
        return account.plan
    }

    private func subtitle(_ snapshot: UsageSnapshot?) -> Text {
        if let error = snapshot?.error, snapshot?.windows.isEmpty ?? true {
            return Text(error).foregroundStyle(Brand.bad)
        }
        let detail = detailWords()
        guard best else { return Text(detail ?? "Switch").foregroundStyle(Brand.subtle) }
        let lead = Text("Most room").foregroundStyle(Brand.good)
        guard let detail else { return lead }
        return lead + Text(" · \(detail)").foregroundStyle(Brand.subtle)
    }

    private func subtitleWords(_ snapshot: UsageSnapshot?) -> String {
        if let error = snapshot?.error, snapshot?.windows.isEmpty ?? true { return error }
        return [best ? "Most room" : nil, detailWords()].compactMap { $0 }.joined(separator: ", ")
    }
}

private struct AddRow: View {
    @EnvironmentObject private var store: AccountStore
    let provider: Provider

    var body: some View {
        Button { store.beginAdd(provider) } label: {
            HStack(spacing: 8) {
                Icon("plus", size: 13)
                Text("Add \(provider.shortName) account")
                Spacer()
            }
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle(quiet: true))
        .disabled(store.addingFor != nil || store.switching != nil)
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

private struct EmptyPanel: View {
    @EnvironmentObject private var store: AccountStore
    let provider: Provider

    var body: some View {
        VStack(spacing: 10) {
            ProviderMark(provider: provider, tint: Brand.text)
                .frame(width: 22, height: 22)
                .padding(.bottom, 2)
            Text("No \(provider.name) account yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.text)
            Text("Sign in to \(provider.name) as usual and Keyhop saves the login. Add more accounts to switch between them.")
                .font(.system(size: 12))
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add account") { store.beginAdd(provider) }
                .buttonStyle(AppButtonStyle(kind: .primary, size: .small))
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
    @ObservedObject private var updater = Updater.shared
    @AppStorage("autoRefresh") private var autoRefresh = true
    @AppStorage("checkForUpdates") private var checkForUpdates = true
    @AppStorage("autoInstallUpdates") private var autoInstallUpdates = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(\.staticSnapshot) private var staticSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Button("Open Keyhop") { AppWindow.show() }
                .buttonStyle(AppButtonStyle(kind: .primary, size: .small))
                .help("Open Keyhop's window")

            Spacer(minLength: 8)

            Button { store.refresh() } label: {
                HStack(spacing: 6) {
                    TimelineView(.animation(paused: !store.isRefreshing)) { context in
                        Icon("refresh", size: 13)
                            .rotationEffect(.degrees(store.isRefreshing ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360 : 0))
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(updatedText(context.date))
                            .fixedSize()
                    }
                }
            }
            .buttonStyle(AppButtonStyle(kind: .ghost, size: .small))
            .help("Refresh usage")

            Button { Task { await updater.check(userInitiated: true) } } label: {
                HStack(spacing: 6) {
                    Icon("update", size: 13)
                    Text(updater.phase == .checking ? "Checking…" : Updater.currentVersion)
                        .fixedSize()
                }
            }
            .buttonStyle(AppButtonStyle(kind: .ghost, size: .small))
            .disabled(updater.phase == .checking || updater.phase == .downloading || updater.phase == .installing)
            .help("Check for updates")
            .accessibilityLabel("Check for updates, version \(Updater.currentVersion)")

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
        .overlay(alignment: .top) { RowDivider() }
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
        if store.isRefreshing { return "Updating" }
        guard let last = store.lastRefresh else { return "Refresh" }
        let minutes = Int(now.timeIntervalSince(last) / 60)
        return minutes < 1 ? "Just now" : "\(minutes)m ago"
    }
}
#endif
