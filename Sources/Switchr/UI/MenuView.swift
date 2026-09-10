import ServiceManagement
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var store: AccountStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Provider.allCases) { ProviderSection(provider: $0) }
            if let notice = store.notice {
                Text(LocalizedStringKey(notice))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .contentShape(Rectangle())
                    .onTapGesture { store.notice = nil }
                    .help("Click to dismiss")
            }
            FooterView()
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: 348)
    }
}

private struct ProviderSection: View {
    @EnvironmentObject private var store: AccountStore
    let provider: Provider

    var body: some View {
        let accounts = store.accounts(for: provider)
        let adding = store.addingFor == provider

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                ProviderMark(provider: provider)
                    .frame(width: 13, height: 13)
                Text(provider.name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if adding {
                    ProgressView().controlSize(.mini)
                    QuietButton("Cancel") { store.cancelAdd() }
                } else {
                    QuietButton("Add account") { store.beginAdd(provider) }
                        .disabled(store.addingFor != nil || store.switching != nil)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 3)

            if adding {
                Text(LocalizedStringKey(provider.signInHint))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
            } else if accounts.isEmpty {
                Text("Sign in to \(provider.name) and the account appears here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 18)
            }

            ForEach(accounts) { AccountRow(account: $0) }
        }
    }
}

private struct FooterView: View {
    @EnvironmentObject private var store: AccountStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack(spacing: 12) {
            Button { store.refresh() } label: {
                HStack(spacing: 5) {
                    TimelineView(.animation(paused: !store.isRefreshing)) { context in
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9.5, weight: .semibold))
                            .rotationEffect(.degrees(store.isRefreshing ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360 : 0))
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(updatedText(now: context.date))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            .buttonStyle(QuietStyle())
            .help("Refresh usage")

            Spacer()

            QuietButton("Insights") { InsightsWindow.show() }

            Toggle("Open at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .foregroundStyle(.secondary)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        store.notice = "Open at login needs Switchr in Applications."
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            QuietButton("Quit") { NSApp.terminate(nil) }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 18)
        .padding(.top, 2)
    }

    private func updatedText(now: Date) -> String {
        if store.isRefreshing { return "Updating" }
        guard let last = store.lastRefresh else { return "Refresh" }
        let minutes = Int(now.timeIntervalSince(last) / 60)
        return minutes < 1 ? "Just now" : "\(minutes)m ago"
    }
}

/// Secondary text action: no chrome, brightens on hover.
struct QuietButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(QuietStyle())
            .font(.system(size: 11, weight: .medium))
    }
}

struct QuietStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietLabel(configuration: configuration)
    }

    private struct QuietLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(hovering && isEnabled ? .primary : .secondary)
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.45)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}
