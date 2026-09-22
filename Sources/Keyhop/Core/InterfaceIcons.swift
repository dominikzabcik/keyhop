import Foundation

/// Keyhop's interface icons: 16-point strokes with round caps. The dashboard page and the Mac app
/// draw them from these shapes, so every surface uses the same set.
enum InterfaceIcons {
    static let shapes: [(name: String, body: String)] = [
        ("overview", #"<rect x="2" y="2" width="5" height="5" rx="1.2"/><rect x="9" y="2" width="5" height="5" rx="1.2"/><rect x="2" y="9" width="5" height="5" rx="1.2"/><rect x="9" y="9" width="5" height="5" rx="1.2"/>"#),
        ("accounts", #"<circle cx="6" cy="5.5" r="2.5"/><path d="M1.8 13.5c.5-2.3 2.2-3.5 4.2-3.5s3.7 1.2 4.2 3.5"/><path d="M10.5 3.2a2.4 2.4 0 0 1 0 4.6"/><path d="M12.2 10.3c1.1.5 1.8 1.6 2 3.2"/>"#),
        ("usage", #"<path d="M2 13.5h12"/><path d="M4 11V7"/><path d="M8 11V3.5"/><path d="M12 11V5.5"/>"#),
        ("budgets", #"<rect x="1.8" y="3.5" width="12.4" height="9" rx="1.8"/><path d="M1.8 6.5h12.4"/><path d="M10.5 9.8h1.5"/>"#),
        ("leaderboard", #"<rect x="1.8" y="8" width="4" height="5.5" rx="1"/><rect x="6" y="3.5" width="4" height="10" rx="1"/><rect x="10.2" y="10" width="4" height="3.5" rx="1"/>"#),
        ("settings", #"<path d="M2 4.5h6"/><path d="M11 4.5h3"/><circle cx="9.5" cy="4.5" r="1.5"/><path d="M2 11.5h2"/><path d="M7 11.5h7"/><circle cx="5.5" cy="11.5" r="1.5"/>"#),
        ("refresh", #"<path d="M13.5 8a5.5 5.5 0 0 1-9.6 3.6"/><path d="M2.5 8a5.5 5.5 0 0 1 9.6-3.6"/><path d="M12.3 1.8v2.8H9.5"/><path d="M3.7 14.2v-2.8h2.8"/>"#),
        ("update", #"<path d="M8 2.5v7.5"/><path d="M5 7l3 3 3-3"/><path d="M3 13.5h10"/>"#),
        ("alert", #"<path d="M8 2.2 14.3 13H1.7z"/><path d="M8 6.5v3"/><path d="M8 11.4v.1"/>"#),
        ("plus", #"<path d="M8 3.5v9M3.5 8h9"/>"#),
        ("more", #"<g stroke-width="2.2"><path d="M3.5 8h.01"/><path d="M8 8h.01"/><path d="M12.5 8h.01"/></g>"#),
        // Keyhop's own: a hop from one key to another, for jumping anywhere in the window.
        ("hop", #"<rect x="1.8" y="9.6" width="4" height="4" rx="1"/><rect x="10.2" y="9.6" width="4" height="4" rx="1"/><path d="M3.8 7.6C4.6 3.6 11.4 3.6 12.2 7.6"/><path d="M10.2 6.6l2 1.1 1.1-2"/>"#),
    ]

    /// `<symbol>` elements for the dashboard page, used as `#i-<name>`.
    static var symbols: String {
        shapes.map { #"<symbol id="i-\#($0.name)" viewBox="0 0 16 16">\#($0.body)</symbol>"# }.joined(separator: "\n  ")
    }

    /// One icon as a standalone black SVG, for template images.
    static func svg(_ name: String) -> String {
        let body = shapes.first { $0.name == name }?.body ?? ""
        return ##"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="#000" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">\##(body)</svg>"##
    }
}
