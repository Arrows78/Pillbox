import AppKit
import Carbon.HIToolbox

/// Shows the keys you press in the notch, for demos and screen shares. Off by default.
/// Nothing is stored or sent, and nothing is shown while macOS secure input is on (password fields).
@MainActor
final class KeystrokeHUD {
    static let shared = KeystrokeHUD()
    private var monitor: Any?
    private var buffer = ""
    private var last = Date.distantPast

    var enabled: Bool { UserDefaults.standard.bool(forKey: "keystrokeHUD") }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { e in
            DispatchQueue.main.async { MainActor.assumeIsolated { KeystrokeHUD.shared.handle(e) } }
        }
    }

    private func handle(_ e: NSEvent) {
        guard enabled, !IsSecureEventInputEnabled() else { return }
        let mods = e.modifierFlags.intersection([.control, .option, .shift, .command])
        let isShortcut = !mods.intersection([.control, .option, .command]).isEmpty
        let shortcutsOnly = UserDefaults.standard.object(forKey: "shortcutsOnly") as? Bool ?? true
        if shortcutsOnly && !isShortcut { return }

        var label = ""
        if mods.contains(.control) { label += "⌃" }
        if mods.contains(.option) { label += "⌥" }
        if mods.contains(.shift) { label += "⇧" }
        if mods.contains(.command) { label += "⌘" }
        label += Self.name(for: e)

        // Typed text accumulates for a moment; shortcuts replace each other.
        if isShortcut || Date().timeIntervalSince(last) > 1.2 || buffer.count > 14 { buffer = label } else { buffer += label }
        last = Date()
        NotchModel.shared.show(Activity(symbol: "keyboard", title: buffer, tint: .white, duration: 1.4, priority: .low))
    }

    private static func name(for e: NSEvent) -> String {
        switch Int(e.keyCode) {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        default: return (e.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}
