#if os(macOS)
import ServiceManagement
import SwiftUI

/// The menu bar panel, the Coss Blue board "BC 1": a short night field with what needs you and the
/// pet, a ring per tool with what its login in use has left, the one hop that helps or the one
/// thing that needs you, and Open, Refresh and More along the bottom. A ring opens that tool's
/// logins, to switch or rename. It opens on the last reading at once; a read runs quietly behind.
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

            // One thing at most: the hop that helps, or else what needs you.
            if let hop = facts.hop {
                HopCard(hop: hop)
            } else if let warning = facts.warning {
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
        .task {
            if pet == nil { pet = PetCache.pet }
            if let loaded = await PetCache.load() { pet = loaded }
        }
    }
}

/// The pet, kept between openings so the menu never waits on the network to show it. It is read
/// again at most every quarter hour.
@MainActor
private enum PetCache {
    static var pet: CloudPet?
    private static var loadedAt: Date?

    /// A failed load keeps the last pet. The status icon stays the limit glyph either way.
    static func load() async -> CloudPet? {
        guard let link = CloudLink.load() else {
            pet = nil
            return nil
        }
        if let loadedAt, Date().timeIntervalSince(loadedAt) < 15 * 60 { return pet }
        loadedAt = Date()
        if let loaded = try? await CloudClient(server: link.server, token: link.token).pet() {
            pet = loaded
        }
        return pet
    }
}

// MARK: Field

/// The pet's night as a short header: the stage and how many logins, then in a sentence what
/// needs you, if anything, and today's tokens. Only what the tools report; no pooled figure and
/// no guess at a reset.
private struct MenuField: View {
    @EnvironmentObject private var store: AccountStore
    let facts: MenuFacts
    let pet: CloudPet?

    var body: some View {
        ZStack(alignment: .topLeading) {
            FieldScene()
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(Brand.mono(10.5, weight: .medium))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                Button {
                    AppWindow.show(section: "limits")
                } label: {
                    Text(facts.title)
                        .font(Brand.sans(17, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Brand.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .buttonStyle(.plain)
                .help("Open Limits")
                Text(facts.sub)
                    .font(Brand.sans(12))
                    .foregroundStyle(Brand.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tokensLine)
                    .font(Brand.sans(11.5))
                    .foregroundStyle(Brand.subtle)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .padding(.trailing, 64)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottomTrailing) {
            FieldPet(pet: pet)
                .padding(.trailing, 18)
                .padding(.bottom, 8)
        }
        .frame(minHeight: 104)
        .clipped()
        .accessibilityElement(children: .contain)
    }

    private var label: String {
        let logins = store.accounts.count
        let count = logins == 1 ? "1 login" : "\(logins) logins"
        guard let pet else { return count }
        return "\(pet.stageName) · \(count)"
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
            // The hop runs as one repeating animation, so the sprite is drawn once, not every frame.
            if reduceMotion || staticSnapshot {
                sprite
            } else {
                sprite.phaseAnimator([false, true]) { content, up in
                    content.offset(y: up ? -11 : 0)
                } animation: { up in
                    up ? .easeOut(duration: 0.24).delay(1.44) : .easeIn(duration: 0.24)
                }
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
            .drawingGroup()
        } else {
            PixelMark(tint: Brand.text.opacity(0.8))
                .frame(width: 30, height: 30)
                .padding(.bottom, 4)
        }
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
                .help("\(ring.provider.name): \(ring.login), \(ring.caption.lowercased()). Show its logins")
                .accessibilityLabel("\(ring.provider.name), \(ring.login), \(ring.caption.lowercased())")
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
        VStack(spacing: 7) {
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
            .frame(width: 44, height: 44)
            VStack(spacing: 0) {
                Text(ring.caption)
                    .font(Brand.figure(14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(ring.tone.ink)
                Text(ring.provider.shortName)
                    .font(Brand.sans(11.5))
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(shape.fill(ring.tone == .out ? Brand.red.opacity(0.07) : Color.white.opacity(hovering || open ? 0.05 : 0.025)))
        .overlay(shape.strokeBorder(ring.tone == .out ? Brand.red.opacity(0.28) : Color.white.opacity(open ? 0.16 : 0.06)))
        .contentShape(shape)
        .onHover { hovering = $0 }
    }
}

/// The opened ring's logins: press one to switch to it; rename or remove from its context menu.
/// Past five logins the list scrolls, so the panel always fits under the menu bar.
private struct MenuLogins: View {
    @EnvironmentObject private var store: AccountStore
    let provider: Provider
    let facts: MenuFacts
    @Binding var renaming: UUID?

    private static let shownRows = 5
    private static let rowHeight: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
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
        return HStack(spacing: 8) {
            Circle()
                .fill(on ? Brand.primary : .clear)
                .overlay(Circle().strokeBorder(on ? .clear : Brand.subtle, lineWidth: 1.5))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                EditableName(account: account, font: Brand.sans(13, weight: .medium), renaming: $renaming)
                    .foregroundStyle(Brand.text)
                Text(meta)
                    .font(Brand.sans(11.5))
                    .foregroundStyle(row.signedOut ? Brand.bad : Brand.muted)
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
            } else if row.signedOut {
                Text("Sign in")
                    .font(Brand.sans(12, weight: .medium))
                    .foregroundStyle(Brand.text)
                    .fixedSize()
            } else if let left = row.left {
                Text("\(left)% left")
                    .font(Brand.figure(12))
                    .foregroundStyle(row.lane == .needs ? Brand.bad : Brand.subtle)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The plan and the tightest window, as the window's Limits says it: signed out only when the
    /// tool turned the login down, and a reading that failed shows how old the last one is.
    private var meta: String {
        if row.signedOut { return "Signed out" }
        var parts: [String] = []
        if let plan = row.account.plan { parts.append(plan) }
        if let window = row.tightest { parts.append(window.label) }
        if row.account.isKeptForLast { parts.append("kept for last") }
        if row.readFailed, let at = row.readAt { parts.append("last read \(MenuFacts.ago(at))") }
        return parts.isEmpty ? row.account.provider.name : parts.joined(separator: " · ")
    }
}

// MARK: Hop and warning

/// The one hop that helps most: which login, what it has left, and one button.
private struct HopCard: View {
    @EnvironmentObject private var store: AccountStore
    let hop: MenuHop

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 10) {
            Image(nsImage: Marks.image(for: hop.tool))
                .renderingMode(.template)
                .resizable()
                .frame(width: 16, height: 16)
                .foregroundStyle(Color(white: 0.9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(hop.tool.shortName) has \(hop.fromLeft)% left")
                    .font(Brand.sans(13, weight: .semibold))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                Text("\(hop.to.displayName) has \(hop.toLeft)%")
                    .font(Brand.sans(12))
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Button {
                store.switchTo(hop.to)
            } label: {
                if store.switching == hop.to.id {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Hop")
                }
            }
            .buttonStyle(AppButtonStyle(kind: .primary, size: .small))
            .disabled(store.switching != nil)
            .help("Hop \(hop.tool.name) to \(hop.to.email)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            ZStack {
                shape.fill(Color(hex: "#13151A"))
                shape.fill(RadialGradient(colors: [Brand.primary.opacity(0.2), .clear],
                                          center: .bottomTrailing, startRadius: 0, endRadius: 220))
            }
        }
        .overlay(shape.strokeBorder(Brand.primary.opacity(0.25)))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

/// The login in use that needs you and can't be helped by a hop: what is wrong, and the one thing to do.
private struct WarningLine: View {
    @EnvironmentObject private var store: AccountStore
    let warning: MenuWarning

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Brand.red).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(warning.text)
                .font(Brand.sans(12))
                .foregroundStyle(Brand.bad)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(warning.action.title) {
                switch warning.action {
                case .add: store.beginAdd(warning.account.provider)
                case .open: AppWindow.show(section: "limits")
                }
            }
            .buttonStyle(.plain)
            .font(Brand.sans(12, weight: .semibold))
            .foregroundStyle(Brand.text)
            .fixedSize()
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
    let signedOut: Bool
    var tone: Tone { signedOut || left <= 15 ? .out : left <= 40 ? .low : .fine }
    var caption: String { signedOut ? "Signed out" : "\(left)% left" }
    var id: String { provider.rawValue }
}

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
        var title: String { self == .add ? "Add" : "Limits" }
    }

    let account: Account
    let text: String
    let action: Action
}

private struct MenuRow: Identifiable {
    let account: Account
    let active: Bool
    let lane: MenuLane
    /// What the tightest window has left, as the tools report it; back to 100 once its reset has
    /// passed. Nil when signed out or nothing was read.
    let left: Int?
    let tightest: UsageWindow?
    let signedOut: Bool
    /// The last reading failed (the network, a busy server), so what shows is the one before.
    let readFailed: Bool
    let readAt: Date?
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

    static func make(store: AccountStore, tracker: UsageTracker, now: Date = Date()) -> MenuFacts {
        let rows = store.accounts.map { account -> MenuRow in
            let snapshot = store.usage[account.id]
            let signedOut = snapshot?.signedOut == true
            let windows = signedOut ? [] : (snapshot?.windows ?? [])
            let tightest = windows.min { SmartHop.room($0, now) < SmartHop.room($1, now) }
            let left = tightest.map { Int(SmartHop.room($0, now).rounded()) }
            let lane: MenuLane = signedOut || (left ?? 100) <= 15 ? .needs : left == nil ? .quiet : .room
            return MenuRow(account: account, active: store.active[account.provider] == account.id, lane: lane,
                           left: left, tightest: tightest, signedOut: signedOut,
                           readFailed: snapshot?.error != nil && !signedOut, readAt: snapshot?.fetchedAt)
        }
        // In use first, then the most room; signed-out logins last.
        .sorted { a, b in
            if a.active != b.active { return a.active }
            if a.signedOut != b.signedOut { return !a.signedOut }
            return (a.left ?? -1) > (b.left ?? -1)
        }

        let hop = bestHop(rows: rows, store: store, tracker: tracker, now: now)
        let sentence = headline(rows: rows, hop: hop, empty: store.accounts.isEmpty)
        // The engine's total, so measured-only tools without accounts count too.
        let total = tracker.todayTotal
        return MenuFacts(
            rows: rows, rings: rings(rows: rows), hop: hop,
            warning: hop == nil ? warning(rows: rows) : nil,
            title: sentence.0, sub: sentence.1, tokens: total.tokens.total, cost: total.cost
        )
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours)h ago" : "\(hours / 24)d ago"
    }

    /// Per tool, the login in use, or the roomiest one when none is.
    private static func rings(rows: [MenuRow]) -> [MenuRing] {
        Provider.allCases.compactMap { provider in
            let mine = rows.filter { $0.account.provider == provider }
            let pick = mine.first { $0.active && ($0.left != nil || $0.signedOut) }
                ?? mine.filter { $0.left != nil }.max { ($0.left ?? 0) < ($1.left ?? 0) }
            guard let pick else { return nil }
            return MenuRing(provider: provider, login: pick.account.displayName, left: pick.left ?? 0, signedOut: pick.signedOut)
        }
    }

    /// Only the logins in use: one that is signed out, or nearly out with no login to hop to.
    private static func warning(rows: [MenuRow]) -> MenuWarning? {
        guard let row = rows.first(where: { $0.active && $0.lane == .needs }) else { return nil }
        let account = row.account
        let tool = account.provider.shortName
        if row.signedOut {
            return MenuWarning(account: account, text: "\(tool) on \(account.displayName) is signed out", action: .open)
        }
        let others = rows.filter { $0.account.provider == account.provider && $0.account.id != account.id }
        if others.isEmpty {
            return MenuWarning(account: account, text: "\(tool) has \(row.left ?? 0)% left · no other login",
                               action: Provider.switchable.contains(account.provider) ? .add : .open)
        }
        return MenuWarning(account: account, text: "\(tool) has \(row.left ?? 0)% left · no other login has room", action: .open)
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

    private static func headline(rows: [MenuRow], hop: MenuHop?, empty: Bool) -> (String, String) {
        if empty { return ("Add a login.", "No saved logins yet. Sign in once and Keyhop keeps the login.") }
        if let hop {
            return ("\(hop.tool.shortName) is running low.",
                    "\(brief(hop.from)) has \(hop.fromLeft)% left. \(brief(hop.to)) has \(hop.toLeft)%.")
        }
        if let wall = rows.first(where: { $0.active && $0.lane == .needs }) {
            let tool = wall.account.provider.shortName
            if wall.signedOut { return ("\(tool) is signed out.", "Sign in to \(wall.account.provider.name) again to keep going.") }
            let others = rows.filter { $0.account.provider == wall.account.provider && $0.account.id != wall.account.id }
            let why = others.isEmpty ? "There is no other login to hop to." : "No other \(tool) login has room for a hop."
            return ("\(tool) has \(wall.left ?? 0)% left.", why)
        }
        if rows.contains(where: { $0.active && $0.left != nil }) {
            return ("Every login in use has room.", "Nothing is close to a limit.")
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

/// The same reading as the window: a login with 15% or less left, or one signed out, needs you.
private enum MenuLane {
    case needs, room, quiet
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
                    // Only a read of the limits shows here, and only while one runs. Reading the
                    // local logs happens quietly; it never changes what the menu shows meanwhile.
                    if store.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Icon("refresh", size: 12)
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(updatedText(context.date))
                            .lineLimit(1)
                            .monospacedDigit()
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
        if store.isRefreshing { return "Reading" }
        guard let last = store.lastRefresh else { return "Refresh" }
        return "Read \(MenuFacts.ago(last, now: now))"
    }

    private func updatedAccessibilityText(_ now: Date) -> String {
        if store.isRefreshing { return "Reading the limits" }
        guard let last = store.lastRefresh else { return "Limits have not been read yet" }
        return "Limits read \(last.formatted(.relative(presentation: .named)))"
    }
}
#endif

