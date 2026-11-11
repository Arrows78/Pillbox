import Foundation

/// Web search from the command palette: a default engine, `bang` prefixes (`yt cats`), and `tr` to translate.
enum WebSearch {
    struct Engine: Identifiable { let key, name, bang, template: String; var id: String { key } }

    static let engines: [Engine] = [
        Engine(key: "google", name: "Google", bang: "g", template: "https://www.google.com/search?q=%@"),
        Engine(key: "duckduckgo", name: "DuckDuckGo", bang: "ddg", template: "https://duckduckgo.com/?q=%@"),
        Engine(key: "bing", name: "Bing", bang: "b", template: "https://www.bing.com/search?q=%@"),
        Engine(key: "brave", name: "Brave Search", bang: "br", template: "https://search.brave.com/search?q=%@"),
        Engine(key: "ecosia", name: "Ecosia", bang: "e", template: "https://www.ecosia.org/search?q=%@"),
        Engine(key: "youtube", name: "YouTube", bang: "yt", template: "https://www.youtube.com/results?search_query=%@"),
        Engine(key: "wikipedia", name: "Wikipedia", bang: "w", template: "https://en.wikipedia.org/w/index.php?search=%@"),
        Engine(key: "github", name: "GitHub", bang: "gh", template: "https://github.com/search?q=%@"),
        Engine(key: "maps", name: "Apple Maps", bang: "map", template: "https://maps.apple.com/?q=%@"),
    ]

    private static let unreserved: CharacterSet = {
        var s = CharacterSet.alphanumerics; s.insert(charactersIn: "-._~"); return s
    }()

    static func encode(_ q: String) -> String { q.addingPercentEncoding(withAllowedCharacters: unreserved) ?? q }

    /// The engine and URL for a palette query, or nil for an empty one.
    static func resolve(_ raw: String, defaultKey: String = "google", language: String = Locale.current.language.languageCode?.identifier ?? "en") -> (label: String, url: URL)? {
        let q = raw.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        let parts = q.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[0].lowercased() == TranslateRoute.prefix, let u = URL(string: "https://translate.google.com/?sl=auto&tl=\(language)&op=translate&text=\(encode(parts[1]))") {
            return (TranslateRoute.label, u)
        }
        var engine = engines.first { $0.key == defaultKey } ?? engines[0]
        var text = q
        if parts.count == 2, let e = engines.first(where: { $0.bang == parts[0].lowercased() }) { engine = e; text = parts[1] }
        guard let u = URL(string: engine.template.replacingOccurrences(of: "%@", with: encode(text))) else { return nil }
        return (engine.name, u)
    }
}
