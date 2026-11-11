import Foundation

extension SelfTest {
    static func activityTitleDisplay() {
        // A title is localised once, where the island is made. The island shows it verbatim, so a translated title
        // must not be a key that looks up something else.
        let titles = [localized("Image copied"), localized("Desktop %d", 3), localized("%@ above %@", "AAPL", "200.00"), localized("Archive failed")]
        check("activity title: a localised title is kept as it was made", titles.allSatisfy { Activity(symbol: "bell", title: $0).title == $0 })
        check("activity title: no translated title is itself a key with another text", titles.allSatisfy { NSLocalizedString($0, comment: "") == $0 })
    }
}
