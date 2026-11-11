import Foundation

extension SelfTest {
    static func activityTitleDisplay() {
        // A title is localised once, where the island is made. The island shows it verbatim, so a translated title
        // must not be a key that looks up something else.
        let titles = [localized("Image copied"), localized("Desktop %d", 3), localized("%@ above %@", "AAPL", "200.00"), localized("Archive failed")]
        check("activity title: a localised title is kept as it was made", titles.allSatisfy { Activity(symbol: "bell", title: $0).title == $0 })
        check("activity title: no translated title is itself a key with another text", titles.allSatisfy { NSLocalizedString($0, comment: "") == $0 })
    }

    static func tabPanelSizes() {
        check("panel sizes: a tab's size parses, unknown names and sizes are left out",
              PanelSize.sizes(from: "music=large,bogus=large,terminal=huge,home=compact,=large") == [.music: .large, .home: .compact]
              && PanelSize.sizes(from: nil).isEmpty && PanelSize.sizes(from: "").isEmpty)
        check("panel sizes: Standard is stored as nothing, the others in tab order",
              PanelSize.setting(from: [.terminal: .compact, .music: .large, .home: .standard]) == "music=large,terminal=compact" && PanelSize.setting(from: [:]).isEmpty)
        let sizes: [Tab: PanelSize] = [.music: .large, .clipboard: .compact]
        check("panel sizes: a stored list reads back as it was written", PanelSize.sizes(from: PanelSize.setting(from: sizes)) == sizes)
        check("panel sizes: the sizes grow from compact to large, and Standard is the size every tab had",
              PanelSize.compact.size.width < PanelSize.standard.size.width && PanelSize.standard.size.width < PanelSize.large.size.width
              && PanelSize.compact.size.height < PanelSize.standard.size.height && PanelSize.standard.size.height < PanelSize.large.size.height
              && PanelSize.standard.size == NotchModel.expandedSize)

        UserDefaults.standard.set("music=large,terminal=compact", forKey: Preferences.tabPanelSizes.key)
        defer { UserDefaults.standard.removeObject(forKey: Preferences.tabPanelSizes.key) }
        check("panel sizes: each tab has its own size, and an unlisted tab is Standard",
              PanelSize.of(.music) == .large && PanelSize.of(.terminal) == .compact && PanelSize.of(.timer) == .standard)
        let m = NotchModel()
        m.expand(.music)
        let scale = NotchModel.scale
        check("panel sizes: expanding applies the size of the tab it opens on",
              m.panelSize == .large && m.size(hasWings: false) == CGSize(width: PanelSize.large.size.width * scale, height: PanelSize.large.size.height * scale))
        m.tab = .timer
        check("panel sizes: switching tabs inside the panel keeps its size", m.panelSize == .large && m.size(hasWings: false).width == PanelSize.large.size.width * scale)
        m.collapse()
        m.expand(.terminal)
        check("panel sizes: the next expand applies the next tab's size", m.panelSize == .compact)
    }
}
