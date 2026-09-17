import SwiftUI

@main
struct KeyhopApp: App {
    @StateObject private var store: Store = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--sample-waiting") { return Store(waitingSample: ()) }
        return arguments.contains("--sample") ? Store(sample: ()) : Store()
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Brand.text)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    /// Read so a change of text size redraws every screen at the new scale.
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            if store.isLinked {
                SeasonView()
                    .transition(.offset(y: 12))
            } else {
                LinkView()
                    .transition(.offset(y: -12))
            }
        }
        .id(textSize)
        .animation(.snappy(duration: 0.35), value: store.isLinked)
    }
}

/// Before anything is linked. The phone never sees a computer's accounts, so linking is only saying
/// who you are, and the screen says that much and no more.
///
/// The mark is the whole composition: it hops slowly while the screen waits for you, and quicker
/// once a code is out and the screen is waiting on the browser.
struct LinkView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)

            HopMark(size: 64, hopping: true, period: store.pending == nil ? 2.8 : 1.0)
                .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Every account.")
                    .foregroundStyle(Brand.text)
                Text("One hop away.")
                    .foregroundStyle(Brand.muted)
            }
            .font(.ui(34, .semibold, .largeTitle))
            .fixedSize(horizontal: false, vertical: true)

            Text("Your season, standings and limits, read from Keyhop on your computer.")
                .font(.ui(15, .regular, .subheadline))
                .foregroundStyle(Brand.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Spacer(minLength: 32)
            Spacer(minLength: 0)

            if let pending = store.pending {
                waiting(pending)
            } else {
                start
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: 520, alignment: .leading)
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.3), value: store.pending)
    }

    private var start: some View {
        VStack(spacing: 12) {
            if let problem = store.problem {
                Text(problem)
                    .font(.ui(13, .regular, .footnote))
                    .foregroundStyle(Brand.wrong)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Link with GitHub") { Task { await store.startLink() } }
                .buttonStyle(PressStyle())
            Text("Your computer sends daily totals. This phone only reads them.")
                .font(.ui(12.5, .regular, .footnote))
                .foregroundStyle(Brand.subtle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .transition(.offset(y: 16))
    }

    private func waiting(_ pending: CloudClient.LinkStart) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Approve this code in your browser")
                        .font(.ui(14, .medium, .subheadline))
                        .foregroundStyle(Brand.muted)
                    Text(pending.userCode)
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(Brand.text)
                        .textSelection(.enabled)
                        .accessibilityLabel("Code \(pending.userCode.map(String.init).joined(separator: " "))")
                    Text("This screen moves on by itself once you approve.")
                        .font(.ui(12.5, .regular, .footnote))
                        .foregroundStyle(Brand.subtle)
                }
                .padding(20)
            }
            HStack {
                Button("Open the page again") { store.reopenLink() }
                    .buttonStyle(QuietStyle())
                Spacer()
                Button("Cancel") { store.cancelLink() }
                    .buttonStyle(QuietStyle())
            }
            .padding(.top, 6)
        }
        .transition(.offset(y: 16))
    }
}
