#if os(macOS)
import AppKit

/// Brand marks rendered as template images for the menu.
enum Marks {
    private static var cache: [Provider: NSImage] = [:]

    static func image(for provider: Provider) -> NSImage {
        if let cached = cache[provider] { return cached }
        let image = NSImage(data: Data(ProviderMarks.svg(for: provider).utf8)) ?? NSImage()
        image.isTemplate = true
        cache[provider] = image
        return image
    }
}
#endif
