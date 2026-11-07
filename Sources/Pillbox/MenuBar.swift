import AppKit
import SwiftUI

/// A chevron and a separator in the menu bar: collapsing pushes everything left of the separator off screen.
/// ⌘-drag icons to the left of the separator to hide them.
@MainActor
final class MenuBarHider {
    static let shared = MenuBarHider()
    private var separator: NSStatusItem?
    private var toggleItem: NSStatusItem?
    private(set) var collapsed = false

    nonisolated static func separatorLength(collapsed: Bool) -> CGFloat { collapsed ? 10_000 : 8 }

    func apply() {
        let on = UserDefaults.standard.bool(forKey: "hideMenuBarIcons")
        if on, toggleItem == nil { install() } else if !on { remove() }
    }

    private func install() {
        let t = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        t.autosaveName = "PillboxHideToggle"
        t.button?.target = self; t.button?.action = #selector(toggle)
        let s = NSStatusBar.system.statusItem(withLength: Self.separatorLength(collapsed: false))
        s.autosaveName = "PillboxHideSeparator"
        s.button?.title = "┃"; s.button?.alphaValue = 0.35
        toggleItem = t; separator = s; collapsed = false; refresh()
    }

    private func remove() {
        for i in [toggleItem, separator] { if let i { NSStatusBar.system.removeStatusItem(i) } }
        toggleItem = nil; separator = nil; collapsed = false
    }

    @objc private func toggle() { collapsed.toggle(); refresh() }

    private func refresh() {
        separator?.length = Self.separatorLength(collapsed: collapsed)
        toggleItem?.button?.image = NSImage(systemSymbolName: collapsed ? "chevron.right" : "chevron.left", accessibilityDescription: nil)
    }
}

/// Tabs that pop out as their own menu bar icon with a popover.
@MainActor
final class MenuBarDetach {
    static let shared = MenuBarDetach()
    static let detachable: [Tab] = [.timer, .stocks, .ai, .reminders, .notes, .clipboard]
    private var items: [Tab: NSStatusItem] = [:]
    private let popover: NSPopover = { let p = NSPopover(); p.behavior = .transient; return p }()
    private var shown: Tab?

    static var wanted: Set<Tab> {
        Set((UserDefaults.standard.stringArray(forKey: "detachedTabs") ?? []).compactMap(Tab.init(rawValue:)).filter(detachable.contains))
    }

    func apply() {
        let want = Self.wanted
        for (tab, item) in items where !want.contains(tab) { NSStatusBar.system.removeStatusItem(item); items[tab] = nil }
        for tab in want where items[tab] == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            item.button?.target = self; item.button?.action = #selector(click(_:)); item.button?.identifier = NSUserInterfaceItemIdentifier(tab.rawValue)
            items[tab] = item
        }
    }

    @objc private func click(_ sender: NSStatusBarButton) {
        guard let raw = sender.identifier?.rawValue, let tab = Tab(rawValue: raw) else { return }
        if popover.isShown, shown == tab { popover.performClose(nil); return }
        popover.contentViewController = NSHostingController(rootView: TabContent(tab: tab).padding(14).frame(width: 480, height: 260)
            .background(Color.black).environment(\.colorScheme, .dark).foregroundStyle(.white))
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        shown = tab
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The next calendar event, with a countdown, as text in the menu bar.
@MainActor
final class MenuBarCalendar {
    static let shared = MenuBarCalendar()
    private var item: NSStatusItem?
    private var timer: Timer?

    nonisolated static func label(title: String, start: Date, end: Date, now: Date = Date()) -> String {
        let t = title.count > 22 ? String(title.prefix(21)) + "…" : title
        if now >= start && now < end { return L("%@ · now", t) }
        let mins = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        if mins <= 0 { return L("%@ · now", t) }
        if mins < 60 { return L("%@ · in %d min", t, mins) }
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return "\(t) · \(f.string(from: start))"
    }

    func apply() {
        let on = UserDefaults.standard.bool(forKey: "menuBarCalendar")
        if on, item == nil {
            let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            i.button?.target = self; i.button?.action = #selector(open)
            item = i
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            CalendarService.shared.refresh()
        } else if !on, let i = item {
            NSStatusBar.system.removeStatusItem(i); item = nil; timer?.invalidate()
        }
        refresh()
    }

    private func refresh() {
        guard let b = item?.button else { return }
        if let e = CalendarService.shared.next {
            b.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
            b.title = " " + Self.label(title: e.title, start: e.start, end: e.end)
        } else { b.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil); b.title = "" }
    }

    @objc private func open() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
}
