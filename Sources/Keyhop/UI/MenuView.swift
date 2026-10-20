#if os(macOS)
import ServiceManagement
import SwiftUI

/// The menu bar panel, the Coss Blue board "BC 1": the night field with what is left across your
/// logins and the pet, a ring per tool, the hop when one helps, the one thing that needs you, and
/// Open, Refresh and More along the bottom. A ring opens that tool's logins, to switch or rename.
struct MenuView: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var tracker: UsageTracker
    @State private var pet: CloudPet?
    @State private var opened: Provider?
    @State private var renaming: UUID?

    var body: some View {
        let facts = MenuFacts.make(store: store, tracker: tracker)
        VStack(alignment: .leading, spacing: 0) {
            MenuField(facts: facts, pet: pet)

            if let adding = store.addingFor {
                AddingPanel(provider: adding)
                    .padding([.horizontal, .top], 12)
            }

            if facts.rings.isEmpty {
                EmptyLine()
            } else {
                MenuRings(rings: facts.rings, opened: $opened)
                if let opened, facts.rings.contains(where: { $0.provider == opened }) {
                    MenuLogins(provider: opened, facts: facts, renaming: $renaming)
                }
            }

            if let hop = facts.hop {
                HopCard(hop: hop)
            }

            if let warning = facts.warning {
                WarningLine(warning: warning)
            }

            if let notice = store.notice {
                NoticeLine(text: notice)
            }

            UpdateLine()

            MenuFooter()
        }
        .frame(width: 360)
        .background(Brand.panel)
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

// MARK: Field

/// The pet's night as a short header: the stage and how many logins, what is left across them,
/// and when the next window comes back.
private struct MenuField: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var tracker: UsageTracker
    let facts: MenuFacts
    let pet: CloudPet?

    var body: some View {
        ZStack(alignment: .topLeading) {
            FieldScene()
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Brand.mono(11, weight: .medium))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                Button {
                    AppWindow.show(section: "limits")
                } label: {
                    Text(headline)
                        .font(Brand.sans(30, weight: .medium))
                        .tracking(-0.9)
                        .foregroundStyle(Brand.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .buttonStyle(.plain)
                .help("Open Limits: what is left, how fast it goes, and when it comes back")
                Text(facts.resetLine ?? facts.sub)
                    .font(Brand.sans(12))
                    .foregroundStyle(Brand.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tokensLine)
                    .font(Brand.sans(11.5))
                    .foregroundStyle(Brand.subtle)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.trailing, 70)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottomTrailing) {
            FieldPet(pet: pet)
                .padding(.trailing, 24)
                .padding(.bottom, 10)
        }
        .frame(height: 132)
        .clipped()
        .accessibilityElement(children: .contain)
    }

    private var label: String {
        let logins = store.accounts.count
        let count = logins == 1 ? "1 login" : "\(logins) logins"
        guard let pet else { return count }
        return "\(pet.stageName) · \(count)"
    }

    private var headline: String {
        guard let pooled = facts.pooled else { return facts.title }
        return "\(pooled.remaining)% left"
    }

    private var tokensLine: String {
        let tokens = "\(Numbers.tokens(facts.tokens)) tokens today"
        return facts.cost > 0 ? "\(tokens) · \(Numbers.usd(facts.cost))" : tokens
    }
}

/// Stars, two hills and a blue glow where the pet stands, drawn from the board's 360 by 132 scene.
private struct FieldScene: View {
    var body: some View {
        Canvas { context, size in
            let bounds = Path(CGRect(origin: .zero, size: size))
            context.fill(bounds, with: .color(Color(hex: "#13151A")))
            context.fill(bounds, with: .radialGradient(
                Gradient(colors: [Brand.primary.opacity(0.32), Brand.primary.opacity(0)]),
                center: CGPoint(x: size.width * 0.75, y: size.height),
                startRadius: 0, endRadius: size.width * 0.62))
            let sx = size.width / 360
            let sy = size.height / 132
            for star in Self.stars {
                let rect = CGRect(x: star.x * sx, y: star.y * sy, width: star.r, height: star.r)
                context.fill(Path(rect), with: .color(.white.opacity(0.35)))
            }
            context.fill(hill(from: (0, 108), [(60, 96, 130, 100, 190, 104), (250, 108, 310, 94, 360, 98)], sx: sx, sy: sy, size: size),
                         with: .color(Color(hex: "#1C1F26")))
            context.fill(hill(from: (0, 122), [(90, 114, 190, 116, 270, 120), (320, 122, 345, 121, 360, 120)], sx: sx, sy: sy, size: size),
                         with: .color(Color(hex: "#171A20")))
        }
        .accessibilityHidden(true)
    }

    private struct Star {
        let x: CGFloat
        let y: CGFloat
        let r: CGFloat
    }

    /// The same seeded scatter as the board, so the sky doesn't change between openings.
    private static let stars: [Star] = {
        var seed = 11
        func next() -> CGFloat {
            seed = (seed * 9301 + 49297) % 233280
            return CGFloat(seed) / 233280
        }
        var stars: [Star] = []
        for _ in 0..<26 {
            let x = (next() * 360).rounded()
            let y = (next() * 110).rounded()
            stars.append(Star(x: x, y: y, r: next() > 0.85 ? 2 : 1.2))
        }
        return stars
    }()

    /// A hill: from a start point along cubic curves (two controls, then the end), closed along the bottom.
    private func hill(from start: (CGFloat, CGFloat), _ curves: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)],
                      sx: CGFloat, sy: CGFloat, size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: start.0 * sx, y: start.1 * sy))
            for curve in curves {
                path.addCurve(to: CGPoint(x: curve.4 * sx, y: curve.5 * sy),
                              control1: CGPoint(x: curve.0 * sx, y: curve.1 * sy),
                              control2: CGPoint(x: curve.2 * sx, y: curve.3 * sy))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
        }
    }
}

/// The account's pet, painted from the shapes the website computes, hopping on the spot. Without a
/// linked account the field shows Keyhop's mark instead.
private struct FieldPet: View {
    let pet: CloudPet?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticSnapshot) private var staticSnapshot

    var body: some View {
        VStack(spacing: 1) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || staticSnapshot)) { context in
                sprite.offset(y: reduceMotion || staticSnapshot ? 0 : Self.lift(context.date))
            }
            Ellipse()
                .fill(Color.black.opacity(0.45))
                .frame(width: 36, height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pet.map { "Your pet, \($0.caption)" } ?? "Keyhop")
    }

    @ViewBuilder
    private var sprite: some View {
        if let pet, pet.width > 0, pet.height > 0 {
            let height: CGFloat = 52
            let width = height * CGFloat(pet.width) / CGFloat(pet.height)
            Canvas { context, size in
                let scale = size.height / CGFloat(pet.height)
                for shape in pet.shapes {
                    let rect = CGRect(x: CGFloat(shape.x) * scale, y: CGFloat(shape.y) * scale,
                                      width: CGFloat(shape.w) * scale, height: CGFloat(shape.h) * scale)
                    context.fill(Path(rect), with: .color(Color(red: shape.red, green: shape.green, blue: shape.blue).opacity(shape.opacity)))
                }
            }
            .frame(width: width, height: height)
        } else {
            PixelMark(tint: Brand.text.opacity(0.8))
                .frame(width: 30, height: 30)
                .padding(.bottom, 4)
        }
    }

    /// The board's hop: still for most of 2.4 seconds, then up about eleven points and down.
    private static func lift(_ date: Date) -> CGFloat {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
        guard phase > 0.6 else { return 0 }
        return -11 * CGFloat(sin(.pi * (phase - 0.6) / 0.4))
    }
}

// MARK: Rings

/// One ring per tool with a limit: what its login in use has left, red when it is nearly out and
/// amber when it is getting there.
private struct MenuRings: View {
    let rings: [MenuRing]
    @Binding var opened: Provider?

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(rings) { ring in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { opened = opened == ring.provider ? nil : ring.provider }
                } label: {
                    RingTile(ring: ring, open: opened == ring.provider)
                }
                .buttonStyle(.plain)
                .help("\(ring.provider.name): \(ring.left)% left on \(ring.login). Show its logins")
                .accessibilityLabel("\(ring.provider.name), \(ring.left)% left on \(ring.login)")
                .accessibilityHint("Shows its logins")
            }
        }
        .padding(12)
    }
}

private struct RingTile: View {
    let ring: MenuRing
    let open: Bool
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(ring.left) / 100)
                    .stroke(ring.tone.ring, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(nsImage: Marks.image(for: ring.provider))
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color(white: 0.9))
            }
            .frame(width: 48, height: 48)
            VStack(spacing: 0) {
                Text("\(ring.left)%")
                    .font(Brand.figure(15))
                    .foregroundStyle(ring.tone.ink)
                Text(ring.provider.shortName)
                    .font(Brand.sans(11.5))
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(shape.fill(ring.tone == .out ? Brand.red.opacity(0.07) : Color.white.opacity(hovering || open ? 0.05 : 0.025)))
        .overlay(shape.strokeBorder(ring.tone == .out ? Brand.red.opacity(0.28) : Color.white.opacity(open ? 0.16 : 0.06)))
        .contentShape(shape)
        .onHover { hovering = $0 }
    }
}

/// The opened ring's logins: press one to switch to it; rename or remove from its context menu.
private struct MenuLogins: View {
    @EnvironmentObject private var store: AccountStore
    let provider: Provider
    let facts: MenuFacts
    @Binding var renaming: UUID?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(facts.rows.filter { $0.account.provider == provider }) { row in
                MenuLoginRow(row: row, hop: row.account.id == facts.hop?.to.id, renaming: $renaming)
            }
            Button { store.beginAdd(provider) } label: {
                HStack(spacing: 8) {
                    Icon("plus", size: 13)
                    Text("Add a \(provider.shortName) login")
                    Spacer()
                }
                .font(Brand.sans(12.5, weight: .medium))
                .padding(.horizontal, 8)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle(quiet: true, radius: 8))
            .disabled(store.addingFor != nil || store.switching != nil || !Provider.switchable.contains(provider))
        }
        .padding(4)
        .background(shape.fill(Color.white.opacity(0.025)))
        .overlay(shape.strokeBorder(Brand.border))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
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
            Circle()
                .fill(on ? Brand.primary : .clear)
                .overlay(Circle().strokeBorder(on ? .clear : Brand.subtle, lineWidth: 1.5))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                EditableName(account: account, font: Brand.sans(13, weight: .medium), renaming: $renaming)
                    .foregroundStyle(row.lane == .needs ? Brand.warn : Brand.text)
                Text(meta(snapshot))
                    .font(Brand.sans(11.5))
                    .foregroundStyle(failed ? Brand.bad : Brand.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            if store.switching == account.id {
                ProgressView().controlSize(.small)
            } else if hop {
                Text("Hop")
                    .font(Brand.sans(12, weight: .semibold))
                    .foregroundStyle(Brand.onPrimary)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .fixedSize()
                    .background(Capsule().fill(Brand.primary))
            } else if let used = row.used {
                Text("\(max(0, 100 - Int(used.rounded())))% left")
                    .font(Brand.figure(12))
                    .foregroundStyle(row.lane == .needs ? Brand.warn : Brand.subtle)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minHeight: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func meta(_ snapshot: UsageSnapshot?) -> String {
        if snapshot?.error != nil, snapshot?.windows.isEmpty ?? true { return "Login expired" }
        var parts: [String] = []
        if let plan = row.account.plan { parts.append(plan) }
        if let window = row.tightest {
            parts.append(window.label)
        }
        return parts.isEmpty ? row.account.provider.name : parts.joined(separator: " · ")
    }
}

// MARK: Hop and warning

/// The one hop that helps most, as one full-width button.
private struct HopCard: View {
    @EnvironmentObject private var store: AccountStore
    let hop: MenuHop

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: Marks.image(for: hop.tool))
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Color(white: 0.9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(hop.tool.name) is at \(hop.fromUsed)%")
                        .font(Brand.sans(13, weight: .semibold))
                        .foregroundStyle(Brand.text)
                    Text("\(hop.to.displayName) has \(max(0, 100 - hop.toUsed))% left")
                        .font(Brand.sans(12))
                        .foregroundStyle(Brand.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Button {
                store.switchTo(hop.to)
            } label: {
                if store.switching == hop.to.id {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Hop to \(hop.to.displayName)")
                        .truncationMode(.middle)
                }
            }
            .buttonStyle(AppButtonStyle(kind: .primary, size: .regular, fullWidth: true))
            .disabled(store.switching != nil)
        }
        .padding(14)
        .background {
            ZStack {
                shape.fill(Color(hex: "#13151A"))
                shape.fill(RadialGradient(colors: [Brand.primary.opacity(0.2), .clear],
                                          center: .bottomTrailing, startRadius: 0, endRadius: 260))
            }
        }
        .overlay(shape.strokeBorder(Brand.primary.opacity(0.25)))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

/// The login that needs you and can't be helped by a hop: what is wrong, and the one thing to do.
private struct WarningLine: View {
    @EnvironmentObject private var store: AccountStore
    let warning: MenuWarning

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Brand.red).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(warning.text)
                .font(Brand.sans(12))
                .foregroundStyle(Brand.bad)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(warning.action.title) {
                switch warning.action {
                case .add: store.beginAdd(warning.account.provider)
                case .open: AppWindow.show(section: "limits")
                }
            }
            .buttonStyle(.plain)
            .font(Brand.sans(12, weight: .semibold))
            .foregroundStyle(Brand.text)
            .disabled(warning.action == .add && store.addingFor != nil)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

/// Before the first login: what to do, said once.
private struct EmptyLine: View {
    var body: some View {
        Text("No limits to read yet. Add a login from More, and Keyhop keeps it.")
            .font(Brand.sans(12.5))
            .foregroundStyle(Brand.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
    }
}

// MARK: Facts

private struct MenuRing: Identifiable {
    enum Tone { case out, low, fine
        var ring: Color {
            switch self {
            case .out: Brand.red
            case .low: Brand.warn
            case .fine: Color(white: 0.9)
            }
        }
        var ink: Color {
            switch self {
            case .out: Brand.bad
            case .low, .fine: Brand.text
            }
        }
    }

    let provider: Provider
    let login: String
    let left: Int
    var tone: Tone { left <= 15 ? .out : left <= 40 ? .low : .fine }
    var id: String { provider.rawValue }
}

private struct MenuHop {
    let tool: Provider
    let from: Account
    let to: Account
    let fromUsed: Int
    let toUsed: Int
}

private struct MenuWarning {
    enum Action: Equatable {
        case add, open
        var title: String { self == .add ? "Add" : "Limits" }
    }

    let account: Account
    let text: String
    let action: Action
}

private struct MenuRow: Identifiable {
    let account: Account
    let lane: MenuLane
    let used: Double?
    let tightest: UsageWindow?
    var id: UUID { account.id }
}

@MainActor
private struct MenuFacts {
    let rows: [MenuRow]
    let rings: [MenuRing]
    let hop: MenuHop?
    let warning: MenuWarning?
    let title: String
    let sub: String
    let tokens: Int
    let cost: Double
    /// Every login with a limit, pooled: what is left across them and what a full set would be,
    /// the window's Limits rule (100 less each login's tightest window; a signed-out login is
    /// not counted). Nil when no login has a limit to read.
    let pooled: (remaining: Int, capacity: Int)?
    /// The soonest window to come back and what it gives the pool, as Limits says it.
    let resetLine: String?

    static func make(store: AccountStore, tracker: UsageTracker, now: Date = Date()) -> MenuFacts {
        let rows = store.accounts.map { account -> MenuRow in
            let windows = store.usage[account.id]?.windows ?? []
            let active = store.active[account.provider] == account.id
            return MenuRow(
                account: account,
                lane: MenuStatus.lane(account, active: active, usage: store.usage, forecasts: tracker.forecasts, now: now),
                used: windows.map(\.usedPercent).max(),
                tightest: windows.max { $0.usedPercent < $1.usedPercent }
            )
        }.sorted { ($0.used ?? -1) > ($1.used ?? -1) }

        let hop = bestHop(store: store)
        let sentence = headline(rows: rows, hop: hop, empty: store.accounts.isEmpty)
        // The engine's total, so measured-only tools without accounts count too.
        let total = tracker.todayTotal
        let counted = rows.filter { row in
            row.used != nil && store.usage[row.account.id]?.error == nil
        }
        let pooled: (remaining: Int, capacity: Int)? = counted.isEmpty ? nil : (
            remaining: Int(counted.reduce(0.0) { $0 + max(0, 100 - min(100, $1.used ?? 0)) }.rounded()),
            capacity: counted.count * 100
        )
        return MenuFacts(
            rows: rows, rings: rings(rows: rows, store: store), hop: hop,
            warning: warning(rows: rows, hop: hop, store: store, tracker: tracker, now: now),
            title: sentence.0, sub: sentence.1, tokens: total.tokens.total, cost: total.cost,
            pooled: pooled, resetLine: resetLine(counted, store: store, now: now)
        )
    }

    /// Per tool, the login in use, or the roomiest one when none is.
    private static func rings(rows: [MenuRow], store: AccountStore) -> [MenuRing] {
        Provider.allCases.compactMap { provider in
            let mine = rows.filter { $0.account.provider == provider && $0.used != nil }
            guard !mine.isEmpty else { return nil }
            let pick = mine.first { store.active[provider] == $0.account.id } ?? mine.min { ($0.used ?? 0) < ($1.used ?? 0) }!
            let left = max(0, 100 - Int(min(100, pick.used ?? 0).rounded()))
            return MenuRing(provider: provider, login: pick.account.displayName, left: left)
        }
    }

    private static func resetLine(_ counted: [MenuRow], store: AccountStore, now: Date) -> String? {
        var best: (at: Date, gain: Int)?
        for row in counted {
            let windows = store.usage[row.account.id]?.windows ?? []
            guard let tightest = row.tightest, let at = tightest.resetsAt, at > now else { continue }
            let rest = windows.filter { $0.label != tightest.label }.map(\.usedPercent).max() ?? 0
            let gain = Int((min(100, tightest.usedPercent) - min(100, rest)).rounded())
            guard gain >= 1 else { continue }
            if best == nil || at < best!.at { best = (at, gain) }
        }
        guard let best else { return nil }
        return "Next reset +\(best.gain)% at \(best.at.formatted(date: .omitted, time: .shortened))"
    }

    private static func warning(rows: [MenuRow], hop: MenuHop?, store: AccountStore, tracker: UsageTracker, now: Date) -> MenuWarning? {
        guard let row = rows.first(where: { $0.lane == .needs && $0.account.id != hop?.from.id && $0.account.provider != hop?.tool }) else { return nil }
        let account = row.account
        let tool = account.provider.shortName
        if store.usage[account.id]?.error != nil, store.usage[account.id]?.windows.isEmpty ?? true {
            return MenuWarning(account: account, text: "\(tool) on \(account.displayName) is signed out", action: .open)
        }
        let when = "is at \(Int((row.used ?? 0).rounded()))%"
        let others = rows.filter { $0.account.provider == account.provider && $0.account.id != account.id }
        if others.isEmpty {
            return MenuWarning(account: account, text: "\(tool) \(when) · no other login", action: Provider.switchable.contains(account.provider) ? .add : .open)
        }
        return MenuWarning(account: account, text: "\(tool) \(when) · no login with room", action: .open)
    }

    private static func bestHop(store: AccountStore) -> MenuHop? {
        var best: (hop: MenuHop, gap: Double)?
        for tool in Provider.allCases {
            let accounts = store.accounts(for: tool)
            guard let activeID = store.active[tool], let current = accounts.first(where: { $0.id == activeID }),
                  let currentUsed = used(current, store: store) else { continue }
            let pick = accounts
                .filter { $0.id != current.id && store.usage[$0.id]?.error == nil && !(store.usage[$0.id]?.windows.isEmpty ?? true) }
                .min { (used($0, store: store) ?? 101) < (used($1, store: store) ?? 101) }
            guard let pick, let pickUsed = used(pick, store: store), pickUsed + 15 < currentUsed else { continue }
            let gap = currentUsed - pickUsed
            if best == nil || gap > best!.gap {
                best = (MenuHop(tool: tool, from: current, to: pick,
                                fromUsed: Int(currentUsed.rounded()), toUsed: Int(pickUsed.rounded())), gap)
            }
        }
        return best?.hop
    }

    private static func used(_ account: Account, store: AccountStore) -> Double? {
        store.usage[account.id]?.windows.map(\.usedPercent).max()
    }

    private static func headline(rows: [MenuRow], hop: MenuHop?, empty: Bool) -> (String, String) {
        if let hop {
            return ("\(hop.tool.shortName) still has room.",
                    "\(Self.brief(hop.from)) is in use at \(hop.fromUsed)%. \(Self.brief(hop.to)) is at \(hop.toUsed)%.")
        }
        if let wall = rows.first(where: { $0.lane == .needs }) {
            let n = Int((wall.used ?? 0).rounded())
            let others = rows.filter { $0.account.provider == wall.account.provider && $0.account.id != wall.account.id }
            let why = others.isEmpty ? "There is no other login to hop to."
                : others.contains(where: { $0.lane == .needs }) ? "The other \(wall.account.provider.shortName) logins are close to a limit too."
                : "No other \(wall.account.provider.shortName) login has enough more room for a hop."
            return ("\(wall.account.provider.shortName) is at \(n)%.", why)
        }
        if empty { return ("Add a login.", "No saved accounts yet. Sign in once and Keyhop keeps the login.") }
        return ("Every login in use has room.", "Nothing is close to a limit.")
    }

    /// Two logins often share a name. The domain is what tells them apart.
    private static func brief(_ account: Account) -> String {
        let name = account.displayName
        guard let at = name.lastIndex(of: "@") else { return name }
        let domain = name[name.index(after: at)...]
        return domain.isEmpty ? name : String(domain)
    }
}

/// The same reading as the window: a login at 85% or more, or one signed out.
private enum MenuLane {
    case needs, active, room, quiet
}

private enum MenuStatus {
    static func lane(_ account: Account, active: Bool, usage: [UUID: UsageSnapshot], forecasts: [String: Date], now: Date = Date()) -> MenuLane {
        let windows = usage[account.id]?.windows ?? []
        if usage[account.id]?.error != nil, windows.isEmpty { return .needs }
        if windows.isEmpty { return .quiet }
        if windows.contains(where: { $0.usedPercent >= 85 }) { return .needs }
        return active ? .active : .room
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

/// Open, Refresh and More, three equal cells split by hairlines. More holds the settings, adding a
/// login and Quit.
private struct MenuFooter: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var tracker: UsageTracker
    @ObservedObject private var updater = Updater.shared
    @AppStorage("autoRefresh") private var autoRefresh = true
    @AppStorage("autoHop") private var autoHop = false
    @AppStorage("checkForUpdates") private var checkForUpdates = true
    @AppStorage("autoInstallUpdates") private var autoInstallUpdates = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(\.staticSnapshot) private var staticSnapshot

    var body: some View {
        HStack(spacing: 0) {
            Button { AppWindow.show() } label: {
                cell { Text("Open"); key("⌘O") }
            }
            .buttonStyle(RowButtonStyle())
            .keyboardShortcut("o")
            .help("Open Keyhop's window")

            Divider().frame(height: 40).overlay(Brand.border)

            Button { store.refresh() } label: {
                cell {
                    TimelineView(.animation(paused: !store.isRefreshing)) { context in
                        Icon("refresh", size: 12)
                            .rotationEffect(.degrees(store.isRefreshing ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360 : 0))
                    }
                    TimelineView(.periodic(from: .now, by: store.isRefreshing || tracker.isUpdating ? 0.25 : 30)) { context in
                        Text(updatedText(context.date))
                            .lineLimit(1)
                            .accessibilityLabel(updatedAccessibilityText(context.date))
                    }
                }
            }
            .buttonStyle(RowButtonStyle())
            .keyboardShortcut("r")
            .help("Refresh usage")

            Divider().frame(height: 40).overlay(Brand.border)

            if staticSnapshot {
                cell { Text("More"); key("⌘Q") }
            } else {
                moreMenu
            }
        }
        .frame(height: 40)
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

    private func cell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 7) { content() }
            .font(Brand.sans(12))
            .foregroundStyle(Color(white: 0.9))
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Rectangle())
    }

    private func key(_ text: String) -> some View {
        Text(text)
            .font(Brand.mono(10.5))
            .foregroundStyle(Brand.subtle)
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
            Toggle("Check for updates automatically", isOn: $checkForUpdates)
            Toggle("Install updates automatically", isOn: $autoInstallUpdates)
                .disabled(!checkForUpdates)
            Toggle("Open at login", isOn: $launchAtLogin)
            Divider()
            Button("Quit Keyhop") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Text("More")
                .font(Brand.sans(12))
                .foregroundStyle(Color(white: 0.9))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(maxWidth: .infinity, minHeight: 40)
        .help("Settings, adding a login, and Quit")
        .accessibilityLabel("More")
    }

    private func updatedText(_ now: Date) -> String {
        if let step = store.progress.value { return step.brief }
        if store.isRefreshing { return "Refreshing" }
        if tracker.isUpdating { return "Reading" }
        guard let last = store.lastRefresh else { return "Refresh" }
        let minutes = Int(now.timeIntervalSince(last) / 60)
        return minutes < 1 ? "Now" : "\(minutes)m ago"
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
                        Capsule().fill(Brand.primary)
                            .frame(width: max(2, width * fraction))
                            .animation(.easeOut(duration: 0.3), value: fraction)
                    } else {
                        let phase = reduceMotion ? 0.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.3) / 1.3
                        Capsule().fill(Brand.primary)
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
