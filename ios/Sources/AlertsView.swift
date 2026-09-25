import SwiftUI
import UIKit

/// What the phone may say, and whether iOS is letting it.
struct AlertsView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text("Choose when Keyhop should remind you about an account or season.")
                        .font(.ui(13, .regular, .footnote))
                        .foregroundStyle(Brand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    if store.notificationsAllowed == false {
                        blocked
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 0) {
                            row(title: "When a limit comes back",
                                note: "For an account that is nearly spent, at the moment it resets.",
                                on: $store.alertsForLimits)
                            Divider().overlay(Brand.border).padding(.vertical, 14)
                            row(title: "Seasons and quests",
                                note: "The season's last evening, and 8 pm if today's goals are still open.",
                                on: $store.alertsForSeason)
                        }
                        .padding(18)
                    }
                    .opacity(store.notificationsAllowed == false ? 0.55 : 1)

                    Text("These alerts are scheduled on this phone from times Keyhop already knows. No alert content or prompt text is sent to a server.")
                        .font(.ui(12.5, .regular, .footnote))
                        .foregroundStyle(Brand.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(.snappy, value: store.notificationsAllowed)
            }
            .background(Brand.background)
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Brand.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.ui(16, .semibold, .headline))
                        .foregroundStyle(Brand.text)
                }
            }
        }
        .presentationBackground(Brand.background)
        .task { await store.readAlertPermission() }
        // Coming back from iOS Settings is the moment the answer may have changed.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.readAlertPermission() } }
        }
    }

    /// iOS has said no. The toggles can't change that, so this says where it can be changed.
    private var blocked: some View {
        Card {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notifications are off")
                        .font(.ui(15, .semibold, .headline))
                        .foregroundStyle(Brand.text)
                    Text("Allow them for Keyhop in iOS Settings, and these alerts start.")
                        .font(.ui(12.5, .regular, .footnote))
                        .foregroundStyle(Brand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Settings", destination: url)
                        .font(.ui(14, .semibold, .subheadline))
                        .foregroundStyle(Brand.background)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Brand.text, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(18)
        }
        .transition(.offset(y: -8))
    }

    private func row(title: String, note: String, on: Binding<Bool>) -> some View {
        // The switch carries the title itself, so a screen reader announces the setting it flips.
        // The note explains it underneath rather than inside the control.
        VStack(alignment: .leading, spacing: 3) {
            Toggle(isOn: Binding(get: { on.wrappedValue }, set: { asked in
                on.wrappedValue = asked
                // The prompt arrives with a reason attached: they just asked for this alert.
                if asked { Task { await store.allowAlerts() } }
            })) {
                Text(title)
                    .font(.ui(15, .medium, .subheadline))
                    .foregroundStyle(Brand.text)
            }
            Text(note)
                .font(.ui(12.5, .regular, .footnote))
                .foregroundStyle(Brand.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 60)
                .accessibilityHidden(true)
        }
        .tint(Brand.good)
        .accessibilityHint(note)
        .sensoryFeedback(.selection, trigger: on.wrappedValue)
    }
}
