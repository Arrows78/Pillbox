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

    @objc private func toggle() { collapsed.toggle(); refresh(); scheduleAutoHide() }

    /// Shown icons hide again after the time chosen in Settings, unless they were hidden by then.
    private var autoHide: Timer?
    private func scheduleAutoHide() {
        autoHide?.invalidate(); autoHide = nil
        let after = Preferences.menuBarAutoHide.value
        guard !collapsed, after > 0 else { return }
        autoHide = Timer.scheduledTimer(withTimeInterval: TimeInterval(after), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.collapsed = true; self?.refresh() }
        }
    }

    private func refresh() {
        separator?.length = Self.separatorLength(collapsed: collapsed)
        toggleItem?.button?.image = NSImage(systemSymbolName: collapsed ? "chevron.right" : "chevron.left", accessibilityDescription: nil)
    }
}

/// Tabs that pop out as their own menu bar icon with a popover.
@MainActor
final class MenuBarDetach {
    static let shared = MenuBarDetach()
    /// Every tab that fits a small popover. Home is already the island; Terminal and Prompter need room the popover lacks.
    static let detachable: [Tab] = Tab.allCases.filter { ![.home, .terminal, .prompter].contains($0) }
    private var items: [Tab: NSStatusItem] = [:]
    private let popover: NSPopover = { let p = NSPopover(); p.behavior = .transient; return p }()
    private var shown: Tab?

    static var wanted: Set<Tab> {
        Set((UserDefaults.standard.stringArray(forKey: "detachedTabs") ?? []).compactMap(Tab.init(rawValue:)).filter(detachable.contains))
    }

    static func setWanted(_ tabs: Set<Tab>) {
        UserDefaults.standard.set(tabs.map(\.rawValue).sorted(), forKey: "detachedTabs")
    }

    func apply() {
        let want = Self.wanted
        for (tab, item) in items where !want.contains(tab) { NSStatusBar.system.removeStatusItem(item); items[tab] = nil }
        for tab in want where items[tab] == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            item.button?.target = self; item.button?.action = #selector(click(_:)); item.button?.cell?.representedObject = tab
            items[tab] = item
        }
    }

    @objc private func click(_ sender: NSStatusBarButton) {
        guard let tab = sender.cell?.representedObject as? Tab else { return }
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
        if now >= start && now < end { return localized("%@ · now", t) }
        let mins = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        if mins <= 0 { return localized("%@ · now", t) }
        if mins < 60 { return localized("%@ · in %d min", t, mins) }
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return localized("%@ · %@", t, f.string(from: start))
    }

    func apply() {
        let on = UserDefaults.standard.bool(forKey: "menuBarCalendar")
        if on, item == nil {
            let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            i.button?.target = self; i.button?.action = #selector(open(_:))
            item = i
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            CalendarService.shared.refresh()
        } else if !on, let i = item {
            NSStatusBar.system.removeStatusItem(i); item = nil; timer?.invalidate()
        }
        refresh()
    }

    /// The text shows the next event, unless it is further away than the hours chosen in Settings.
    nonisolated static func showsEvent(starting start: Date, within hours: Int, now: Date = Date()) -> Bool {
        hours <= 0 || start.timeIntervalSince(now) <= TimeInterval(hours) * 3600
    }

    private func refresh() {
        guard let b = item?.button else { return }
        b.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
        if let e = CalendarService.shared.next, Self.showsEvent(starting: e.start, within: Preferences.menuBarCalendarHours.value) {
            b.title = " " + Self.label(title: e.title, start: e.start, end: e.end)
        } else {
            b.title = ""
        }
    }

    /// Today's timed events, with Join for the video calls, and Calendar at the foot.
    @objc private func open(_ sender: NSStatusBarButton) {
        AgendaModel.shared.refresh()
        let menu = NSMenu()
        let today = AgendaModel.shared.events.filter { !$0.allDay && Calendar.current.isDateInToday($0.start) }.sorted { $0.start < $1.start }
        if today.isEmpty { menu.addItem(NSMenuItem(title: localized("No events today"), action: nil, keyEquivalent: "")) }
        let time = DateFormatter(); time.timeStyle = .short; time.dateStyle = .none
        for e in today {
            menu.addItem(boxed("\(time.string(from: e.start))  \(String(e.title.prefix(50)))") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) })
            if let url = e.join { menu.addItem(boxed("    " + localized("Join")) { NSWorkspace.shared.open(url) }) }
        }
        menu.addItem(.separator())
        menu.addItem(boxed(localized("Open Calendar")) { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) })
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    private func boxed(_ title: String, _ run: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runBox(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ActionBox(run)
        return item
    }

    @objc private func runBox(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ActionBox else { return }
        box.run()
    }
}
