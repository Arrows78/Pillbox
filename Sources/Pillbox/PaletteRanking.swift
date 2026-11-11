import Foundation

/// Fuzzy matching for the palette: the query's letters must appear in the title in order, and a match scores higher
/// when the letters are together or start words ("sc" finds "Snap center" before "Keyboard backlight").
enum FuzzyMatch {
    /// The score of `query` against `title`, or nil when a letter of the query is missing. Higher is better.
    static func score(_ query: String, in title: String) -> Int? {
        let q = Array(query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter { !$0.isWhitespace })
        guard !q.isEmpty else { return 0 }
        let t = Array(title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
        var score = 0
        var ti = 0
        var previous = -2
        for ch in q {
            guard let found = t[ti...].firstIndex(of: ch) else { return nil }
            score += 1
            if found == previous + 1 { score += 4 }                                    // a run of letters
            if found == 0 || t[found - 1] == " " || t[found - 1] == "·" { score += 3 } // the start of a word
            previous = found
            ti = found + 1
        }
        return score - t.count / 8   // among equal matches, the shorter title first
    }
}

/// The commands run most recently, at the top of the palette when the query is empty. Kept by title, so a command
/// keeps its place across launches, and only the last few are kept.
enum PaletteRecents {
    static let key = "paletteRecents"
    static let limit = 5

    static var titles: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func record(_ title: String) {
        var list = titles.filter { $0 != title }
        list.insert(title, at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: key)
    }
}

/// What the palette's prefixes mean: `>` keeps only commands, `/` only clipboard items, `f ` (with its space) only files
/// and `w ` only windows; the rest of the query is what they are matched with. Leading spaces are ignored.
enum PalettePrefix: Equatable {
    case commands(String), clipboard(String), files(String), windows(String), none

    init(_ query: String) {
        let s = String(query.drop(while: { $0 == " " }))
        func rest(_ dropping: Int) -> String { String(s.dropFirst(dropping)).trimmingCharacters(in: .whitespaces) }
        if s.hasPrefix(">") { self = .commands(rest(1)) }
        else if s.hasPrefix("/") { self = .clipboard(rest(1)) }
        else if s.hasPrefix("f ") { self = .files(rest(2)) }
        else if s.hasPrefix("w ") { self = .windows(rest(2)) }
        else { self = .none }
    }
}
