import SwiftUI

struct AccountRow: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var tracker: UsageTracker
    let account: Account

    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var isActive: Bool { store.active[account.provider] == account.id }
    private var isSwitching: Bool { store.switching == account.id }

    var body: some View {
        Button { if !editing { store.switchTo(account) } } label: {
            VStack(alignment: .leading, spacing: 7) {
                header
                UsageBlock(account: account.id, snapshot: store.usage[account.id], emphasized: isActive)
                if let spend = tracker.today[account.id], spend.requests > 0 {
                    Text(spendLine(spend))
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle(active: isActive, hovering: hovering))
        .onHover { hovering = $0 }
        .padding(.horizontal, 8)
        .help(isActive ? "\(account.email) is in use" : "Switch \(account.provider.name) to \(account.email)")
        .contextMenu {
            Button("Rename…") {
                draft = account.label ?? ""
                editing = true
                fieldFocused = true
            }
            Button("Refresh usage") { store.refresh() }
            Divider()
            Button("Remove") { store.remove(account) }
                .disabled(isActive)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if editing {
                TextField(account.email, text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .focused($fieldFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { editing = false }
                    .onChange(of: fieldFocused) { _, focused in if !focused { commitRename() } }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(account.displayName)
                            .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? .primary : .secondary)
                            .truncationMode(.middle)
                        if let plan = account.plan {
                            Text(plan)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .layoutPriority(-1)
                        }
                    }
                    if account.label != nil {
                        Text(account.email)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                            .truncationMode(.middle)
                    }
                }
                .lineLimit(1)
            }

            Spacer(minLength: 8)
            trailing
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isSwitching {
            ProgressView().controlSize(.mini)
        } else if isActive {
            Text("In use")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        } else if hovering && store.switching == nil && store.addingFor == nil {
            Text("Switch")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    private func spendLine(_ spend: Totals) -> String {
        var line = "Today \(Numbers.tokens(spend.tokens.total)) tokens · \(Numbers.usd(spend.cost))"
        if let budget = tracker.budget(for: Budget.scope(for: account.id)), budget.amount > 0 {
            let share = (tracker.budgetSpend[budget.scope] ?? 0) / budget.amount
            line += " · \(Int((share * 100).rounded()))% of \(budget.period.adjective) budget"
        }
        return line
    }

    private func commitRename() {
        guard editing else { return }
        editing = false
        store.rename(account, to: draft)
    }
}

private struct RowStyle: ButtonStyle {
    let active: Bool
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let opacity: Double = active ? 0.085 : configuration.isPressed ? 0.08 : hovering ? 0.045 : 0
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(opacity))
            )
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct UsageBlock: View {
    @EnvironmentObject private var tracker: UsageTracker
    let account: UUID
    let snapshot: UsageSnapshot?
    let emphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let snapshot, !snapshot.windows.isEmpty {
                ForEach(snapshot.windows) { window in
                    MeterRow(window: window, emphasized: emphasized,
                             runsOut: tracker.forecasts[UsageTracker.forecastKey(account, window.label)])
                }
                if let error = snapshot.error {
                    Text("\(error) Showing last known usage.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            } else if let error = snapshot?.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if snapshot?.fetchedAt != nil {
                Text("No limits reported for this plan.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                Text("Loading usage…")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct MeterRow: View {
    let window: UsageWindow
    let emphasized: Bool
    /// When the limit runs out at the recent rate, if that's before it resets.
    let runsOut: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 8) {
                Text(window.label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .leading)
                Meter(fraction: window.usedPercent / 100, pace: window.pace(at: context.date), emphasized: emphasized)
                    .frame(height: 10)
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(emphasized ? .primary : .secondary)
                    .frame(width: 36, alignment: .trailing)
                if let runsOut, runsOut > context.date {
                    Text("out \(runsOut.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 66, alignment: .trailing)
                } else {
                    Text(window.resetText(at: context.date))
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 66, alignment: .trailing)
                }
            }
            .help(helpText(now: context.date))
        }
    }

    private func helpText(now: Date) -> String {
        var parts = ["\(Int(window.usedPercent.rounded()))% of the \(window.label.lowercased()) limit used"]
        if let resetsAt = window.resetsAt {
            parts.append("resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))")
        }
        if let runsOut, runsOut > now {
            parts.append("at the recent rate it runs out around \(runsOut.formatted(date: .omitted, time: .shortened))")
        }
        if let pace = window.pace(at: now) {
            parts.append("the tick marks an even pace (\(Int((pace * 100).rounded()))%)")
        }
        return parts.joined(separator: ", ")
    }
}
