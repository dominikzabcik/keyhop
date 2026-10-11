import Foundation

/// The dashboard app: one page of HTML, CSS and JavaScript with no outside resources. Served live by
/// `keyhop dashboard`, or saved with its data inside by `keyhop insights --output`.
enum DashboardPage {
    static func render(boot: String?) -> String {
        // One symbol per tool, from the tool list itself, so a newly added tool always has its mark.
        let marks = Provider.allCases.map { provider in
            #"<symbol id="mark-\#(provider.rawValue)" viewBox="0 0 24 24"><path d="\#(ProviderMarks.path(for: provider))"/></symbol>"#
        }.joined(separator: "\n  ")
        let page = template
            .replacingOccurrences(of: "{{marks}}", with: marks)
            .replacingOccurrences(of: "{{icons}}", with: InterfaceIcons.symbols)
            .replacingOccurrences(of: "{{backdrop}}", with: Backdrop.script)
        // Inside a script element, "<" could close it early; JSON allows it escaped.
        let data = boot.map { $0.replacingOccurrences(of: "<", with: "\\u003c") } ?? "null"
        return page.replacingOccurrences(of: "{{boot}}", with: data)
    }

    /// The page, assembled from its parts in Dashboard/Page. Each part is one raw string, so the
    /// contract tests still read the whole page and a section's script stays readable on its own.
    static let template: String = [
        head,
        "<style>", styles, "</style>",
        shell,
        "(() => {",
        scriptCore, scriptChrome, scriptOverview, scriptAccounts, scriptUsage, scriptBudgets,
        scriptBackdrop, scriptPlans, scriptCloud, scriptSettings, scriptActions,
        tail,
    ].joined(separator: "\n")

    private static let head = ##"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<title>Keyhop</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='7' fill='%23171717'/%3E%3Cg fill='%23EBEBEB'%3E%3Crect x='3.3' y='3.3' width='8' height='26' rx='2'/%3E%3Crect x='12.8' y='12.3' width='8' height='8' rx='2'/%3E%3Crect x='21.3' y='1.3' width='8' height='8' rx='2'/%3E%3Crect x='21.3' y='22.7' width='8' height='8' rx='2'/%3E%3C/g%3E%3C/svg%3E">
"""##

    private static let tail = ##"""
})();
</script>
</body>
</html>
"""##
}
