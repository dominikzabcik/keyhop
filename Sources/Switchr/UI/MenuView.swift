import ServiceManagement
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var store: AccountStore
    @AppStorage("menuTool") private var tool: Provider = .claude
    @State private var renaming: UUID?
    @Namespace private var tabs

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToolTabs(selection: $tool, namespace: tabs)
                .padding(.horizontal, 10)
                .padding(.top, 10)

            ToolPanel(provider: tool, renaming: $renaming)
                .padding(.top, 8)
                .padding(.bottom, 12)

            if let notice = store.notice {
                NoticeLine(text: notice)
            }

            UpdateLine()

            MenuFooter()
        }
        .frame(width: 340)
        .background(Enamel())
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
    @EnvironmentObject private var store: AccountStore
    @Binding var selection: Provider
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Provider.allCases) { provider in
                let selected = provider == selection
                Button {
                    withAnimation(.snappy(duration: 0.28)) { selection = provider }
                } label: {
                    VStack(spacing: 7) {
                        HStack(spacing: 6) {
                            ProviderMark(provider: provider, tint: selected ? Brand.bone : nil)
                                .frame(width: 13, height: 13)
                            Text(provider.shortName)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        TwinTracks(values: inUseLimits(provider))
                            .frame(width: 30, height: 8)
                            .opacity(selected ? 1 : 0.7)
                    }
                    .foregroundStyle(selected ? AnyShapeStyle(Brand.bone) : AnyShapeStyle(.secondary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.white.opacity(0.075))
                                .matchedGeometryEffect(id: "tab", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(provider.name)
                .accessibilityLabel(provider.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func inUseLimits(_ provider: Provider) -> [Double?] {
        guard let id = store.active[provider], let windows = store.usage[id]?.windows else { return [] }
        return windows.prefix(2).map { $0.usedPercent / 100 }
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

        VStack(alignment: .leading, spacing: 0) {
            if store.addingFor == provider {
                AddingPanel(provider: provider)
            } else if accounts.isEmpty {
                EmptyPanel(provider: provider)
            } else {
                if let inUse {
                    InUseHero(account: inUse, renaming: $renaming)
                } else {
                    SignedOutHero(provider: provider)
                }
                VStack(spacing: 2) {
                    ForEach(others) { account in
                        AlternativeRow(account: account, best: account.id == best, renaming: $renaming)
                    }
                    AddRow(provider: provider)
                }
                .padding(.horizontal, 8)
                .padding(.top, 12)
            }
        }
    }

    /// Room left on the tightest limit, in percent.
    private func room(_ account: Account) -> Double? {
        store.usage[account.id]?.windows.map { 100 - $0.usedPercent }.min()
    }
}

private struct InUseHero: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var tracker: UsageTracker
    let account: Account
    @Binding var renaming: UUID?

    var body: some View {
        let snapshot = store.usage[account.id]
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    EditableName(account: account, font: .system(size: 19, weight: .semibold, design: .rounded), renaming: $renaming)
                        .foregroundStyle(Brand.bone)
                    if let plan = account.plan {
                        Text(plan)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                    Spacer(minLength: 8)
                    Text("In use")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if account.label != nil {
                    Text(account.email)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let snapshot, !snapshot.windows.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 22), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                    ForEach(snapshot.windows) { window in
                        LimitCell(window: window, runsOut: tracker.forecasts[UsageTracker.forecastKey(account.id, window.label)])
                    }
                }
                if let error = snapshot.error {
                    Text("\(error) Showing the last reading.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(snapshot?.error ?? (snapshot?.fetchedAt == nil ? "Reading limits…" : "This plan reports no limits."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let spend = tracker.today[account.id], spend.requests > 0 {
                SpendLine(account: account, spend: spend)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename…") { renaming = account.id }
            Button("Refresh usage") { store.refresh() }
        }
    }
}

private struct LimitCell: View {
    let window: UsageWindow
    let runsOut: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let outSoon = runsOut.map { $0 > context.date } ?? false
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text(window.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Text("\(Int(window.usedPercent.rounded()))")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Brand.bone)
                    Text("%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 1)
                }
                LimitTrack(fraction: window.usedPercent / 100, pace: window.pace(at: context.date))
                    .frame(height: 8)
                Text(outSoon ? "Runs out \(runsOut!.formatted(date: .omitted, time: .shortened))" : resetCaption(context.date))
                    .font(.system(size: 11, weight: outSoon ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(outSoon ? AnyShapeStyle(Brand.amber) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
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
        HStack(spacing: 0) {
            Text("Today ")
                .foregroundStyle(.secondary)
            Text(Numbers.tokens(spend.tokens.total))
                .foregroundStyle(Brand.bone)
            Text(" tokens, ")
                .foregroundStyle(.secondary)
            Text(Numbers.usd(spend.cost))
                .foregroundStyle(Brand.bone)
            Spacer(minLength: 8)
            if let budget = tracker.budget(for: Budget.scope(for: account.id)), budget.amount > 0 {
                let share = (tracker.budgetSpend[budget.scope] ?? 0) / budget.amount
                Text("\(Int((share * 100).rounded()))% of \(budget.period.adjective) budget")
                    .foregroundStyle(share >= 0.8 ? AnyShapeStyle(Brand.amber) : AnyShapeStyle(.secondary))
            }
        }
        .font(.system(size: 11.5).monospacedDigit())
        .lineLimit(1)
    }
}

private struct SignedOutHero: View {
    let provider: Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Signed out of \(provider.name)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.bone)
            Text("Pick an account to sign back in.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

private struct AlternativeRow: View {
    @EnvironmentObject private var store: AccountStore
    let account: Account
    let best: Bool
    @Binding var renaming: UUID?
    @State private var hovering = false

    var body: some View {
        let snapshot = store.usage[account.id]
        let limits = snapshot?.windows ?? []
        let room = limits.map { 100 - $0.usedPercent }.min()

        Button {
            if renaming != account.id { store.switchTo(account) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    EditableName(account: account, font: .system(size: 13, weight: .medium), renaming: $renaming)
                        .foregroundStyle(Brand.bone.opacity(0.92))
                    Text(subtitle(snapshot))
                        .font(.system(size: 11))
                        .foregroundStyle(best ? AnyShapeStyle(Brand.amber) : AnyShapeStyle(.secondary))
                        .lineLimit(snapshot?.error != nil && (snapshot?.windows.isEmpty ?? true) ? 2 : 1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if store.switching == account.id {
                    ProgressView().controlSize(.small)
                } else if let room, snapshot?.error == nil {
                    TwinTracks(values: limits.prefix(2).map { $0.usedPercent / 100 })
                        .frame(width: 34, height: 8)
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(Int(room.rounded()))%")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Brand.bone)
                        Text("left")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 62, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.065 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.switching != nil && store.switching != account.id)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("Switch \(account.provider.name) to \(account.email)")
        .accessibilityLabel("Switch to \(account.displayName)")
        .accessibilityValue(room.map { "\(Int($0.rounded())) percent left" } ?? subtitle(snapshot))
        .contextMenu {
            Button("Rename…") { renaming = account.id }
            Divider()
            Button("Remove") { store.remove(account) }
        }
    }

    private func subtitle(_ snapshot: UsageSnapshot?) -> String {
        if let error = snapshot?.error, snapshot?.windows.isEmpty ?? true { return error }
        var parts: [String] = []
        if best { parts.append("Most room") }
        if account.label != nil { parts.append(account.email) } else if let plan = account.plan { parts.append(plan) }
        return parts.isEmpty ? "Switch" : parts.joined(separator: " · ")
    }
}

private struct AddRow: View {
    @EnvironmentObject private var store: AccountStore
    let provider: Provider

    var body: some View {
        Button { store.beginAdd(provider) } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("Add \(provider.shortName) account")
                Spacer()
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietStyle())
        .disabled(store.addingFor != nil || store.switching != nil)
    }
}

private struct AddingPanel: View {
    @EnvironmentObject private var store: AccountStore
    let provider: Provider

    var body: some View {
        VStack(spacing: 14) {
            HandoffMark()
                .frame(width: 58, height: 58)
            Text("Waiting for a new \(provider.name) login")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.bone)
            Text(LocalizedStringKey(provider.signInHint))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            QuietButton("Cancel") { store.cancelAdd() }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
    }
}

private struct EmptyPanel: View {
    @EnvironmentObject private var store: AccountStore
    let provider: Provider

    var body: some View {
        VStack(spacing: 10) {
            ProviderMark(provider: provider)
                .frame(width: 26, height: 26)
            Text("No \(provider.name) account yet")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.bone)
            Text("Sign in to \(provider.name) as usual and Switchr saves the login. Add more accounts to switch between them.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add account") { store.beginAdd(provider) }
                .buttonStyle(BoneButtonStyle())
                .frame(width: 150)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
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
        Text(LocalizedStringKey(text))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
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

    var body: some View {
        HStack(spacing: 16) {
            Button { store.refresh() } label: {
                HStack(spacing: 6) {
                    TimelineView(.animation(paused: !store.isRefreshing)) { context in
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(store.isRefreshing ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360 : 0))
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(updatedText(context.date))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            .buttonStyle(QuietStyle())
            .help("Refresh usage")

            Spacer()

            Button { Task { await updater.check(userInitiated: true) } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text(updater.phase == .checking ? "Checking…" : Updater.currentVersion)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .buttonStyle(QuietStyle())
            .disabled(updater.phase == .checking || updater.phase == .downloading || updater.phase == .installing)
            .help("Check for updates")
            .accessibilityLabel("Check for updates, version \(Updater.currentVersion)")

            QuietButton("Insights") { InsightsWindow.show() }

            Menu {
                Text("Switchr \(Updater.currentVersion)")
                Button("Check for Updates…") { Task { await updater.check(userInitiated: true) } }
                Divider()
                Toggle("Check usage every 5 minutes", isOn: $autoRefresh)
                Toggle("Check for updates automatically", isOn: $checkForUpdates)
                Toggle("Install updates automatically", isOn: $autoInstallUpdates)
                    .disabled(!checkForUpdates)
                Toggle("Open at login", isOn: $launchAtLogin)
                Divider()
                Button("Quit Switchr") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .font(.system(size: 11.5, weight: .medium))
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(Color.black.opacity(0.18))
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                store.notice = "Open at login needs Switchr in Applications."
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private func updatedText(_ now: Date) -> String {
        if store.isRefreshing { return "Updating" }
        guard let last = store.lastRefresh else { return "Refresh" }
        let minutes = Int(now.timeIntervalSince(last) / 60)
        return minutes < 1 ? "Just now" : "\(minutes)m ago"
    }
}
