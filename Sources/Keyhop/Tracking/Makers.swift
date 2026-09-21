import Foundation

/// Who made a model, read from its name.
///
/// A tool isn't a maker: OpenCode, Pi and Cursor run models from several companies, and Claude
/// Code can be pointed at others. Grouping by maker answers "how much of this was Anthropic,
/// how much OpenAI" whichever tool the work went through.
enum Makers {
    /// The maker's name, or "Other" for a model this list doesn't know.
    static func maker(of model: String) -> String {
        let name = Pricing.normalize(model)
        // A provider prefix ("anthropic/claude-sonnet-5") is dropped by normalize; the name
        // after it is what's matched, so a model served through a router keeps its real maker.
        for (maker, prefixes) in table where prefixes.contains(where: { name.hasPrefix($0) }) {
            return maker
        }
        return "Other"
    }

    /// Checked in order; the first maker with a matching prefix wins.
    private static let table: [(String, [String])] = [
        ("Anthropic", ["claude"]),
        ("OpenAI", ["gpt", "o1", "o3", "o4", "codex", "chatgpt", "text-embedding"]),
        ("Google", ["gemini", "gemma", "lyria", "deep-research"]),
        ("xAI", ["grok"]),
        ("DeepSeek", ["deepseek"]),
        ("Z.ai", ["glm"]),
        ("Moonshot AI", ["kimi", "moonshot"]),
        ("Alibaba", ["qwen", "qwq"]),
        ("Mistral", ["mistral", "codestral", "devstral", "magistral"]),
        ("Meta", ["llama"]),
        ("MiniMax", ["minimax"]),
        ("Cursor", ["composer", "cursor"]),
    ]
}
