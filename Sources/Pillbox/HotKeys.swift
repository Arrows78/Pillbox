import Foundation
import AppKit
import SwiftUI
import Carbon.HIToolbox

/// The app's global shortcuts. They are registered at launch and listed in Settings from this one table.
/// A shortcut that another app already owns fails to register; `HotKey` says so and Settings marks it.
enum GlobalShortcut: UInt32, CaseIterable {
    case palette = 1, toggleNotch, pasteNext, dictate

    /// English text of the action (a localisation key).
    var title: String {
        switch self {
        case .palette: "Command palette"
        case .toggleNotch: "Toggle Notch"
        case .pasteNext: "Paste next from the copy stack"
        case .dictate: "Dictate"
        }
    }

    /// UserDefaults switch of an opt-in shortcut; nil means always on.
    var setting: String? { self == .dictate ? "dictationShortcut" : nil }
    var isEnabled: Bool { setting.map { UserDefaults.standard.bool(forKey: $0) } ?? true }

    var key: String {
        switch self { case .palette: "K"; case .toggleNotch: "N"; case .pasteNext: "V"; case .dictate: "D" }
    }

    var keyCode: UInt32 {
        switch self { case .palette: UInt32(kVK_ANSI_K); case .toggleNotch: UInt32(kVK_ANSI_N); case .pasteNext: UInt32(kVK_ANSI_V); case .dictate: UInt32(kVK_ANSI_D) }
    }

    static let modifiers = UInt32(controlKey | optionKey)
    var keycaps: String { "⌃⌥" + key }

    @MainActor func run() {
        switch self {
        case .palette: PaletteController.shared.toggle()
        case .toggleNotch: NotchModel.shared.toggle()
        case .pasteNext: CopyStackStore.shared.pasteNext()
        case .dictate: DictationService.shared.toggle()
        }
    }
}

/// Carbon global hotkey (works without any privacy permission).
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false
    /// Ids of the shortcuts that could not be registered, so Settings does not promise them.
    private(set) static var unavailable: Set<UInt32> = []

    init(keyCode: UInt32, modifiers: UInt32, id: UInt32, handler: @escaping () -> Void) {
        self.id = id
        var ok = true
        if !Self.installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                DispatchQueue.main.async { HotKey.handlers[hk.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
            Self.installed = status == noErr
            ok = Self.installed
        }
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x50424F58), id: id), GetApplicationEventTarget(), 0, &ref)
        ok = ok && status == noErr && ref != nil
        if ok {
            Self.handlers[id] = handler
        } else {
            // Nothing is registered, so no handler: the key does nothing, and the user is told which one.
            ref = nil
            Self.unavailable.insert(id)
            let title = GlobalShortcut(rawValue: id).map { localized("%@ is already used by another app", $0.keycaps) } ?? localized("A shortcut is already used by another app")
            NotchModel.shared.show(Activity(symbol: "keyboard.badge.ellipsis", title: title, tint: .orange))
        }
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil; Self.handlers[id] = nil
    }
}
