import AppKit
import Carbon.HIToolbox

private var hyperHeld = false
private var hyperUsed = false

private func hyperTap(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DispatchQueue.main.async { MainActor.assumeIsolated { HyperKey.shared.reenable() } }
        return Unmanaged.passUnretained(event)
    }
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    if code == Int64(kVK_F18) {
        if type == .keyDown, !hyperHeld { hyperHeld = true; hyperUsed = false }
        else if type == .keyUp {
            hyperHeld = false
            if !hyperUsed, UserDefaults.standard.bool(forKey: "hyperEscape") {
                for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Escape), keyDown: down)?.post(tap: .cghidEventTap) }
            }
        }
        return nil
    }
    if hyperHeld, type == .keyDown || type == .keyUp {
        hyperUsed = true
        event.flags = HyperKey.apply(to: event.flags)
    }
    return Unmanaged.passUnretained(event)
}

/// Caps Lock becomes ⌃⌥⇧⌘. hidutil turns Caps Lock into F18 (until reboot, and undone on quit),
/// and an event tap adds the four modifiers to every key pressed while F18 is held.
@MainActor
final class HyperKey {
    static let shared = HyperKey()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    nonisolated static func apply(to flags: CGEventFlags) -> CGEventFlags {
        flags.union([.maskControl, .maskAlternate, .maskShift, .maskCommand])
    }

    nonisolated static func mappingJSON(enabled: Bool) -> String {
        guard enabled else { return "{\"UserKeyMapping\":[]}" }
        return "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x700000039,\"HIDKeyboardModifierMappingDst\":0x70000006D}]}"
    }

    func apply() { UserDefaults.standard.bool(forKey: "hyperKey") ? enable() : disable() }

    private func enable() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            NotchModel.shared.show(Activity(symbol: "keyboard.badge.ellipsis", title: localized("Accessibility needed"), subtitle: localized("Allow Pillbox, then turn Hyper on again"), tint: .orange))
            UserDefaults.standard.set(false, forKey: "hyperKey"); return
        }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: hyperTap, userInfo: nil) else {
            NotchModel.shared.show(Activity(symbol: "keyboard.badge.ellipsis", title: localized("Could not turn Hyper on"), subtitle: localized("Allow Pillbox in Privacy & Security › Accessibility"), tint: .orange))
            UserDefaults.standard.set(false, forKey: "hyperKey")
            return
        }
        tap = t; source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        Self.hidutil(Self.mappingJSON(enabled: true))
    }

    func disable() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        let was = tap != nil
        tap = nil; source = nil; hyperHeld = false; hyperUsed = false
        if was { Self.hidutil(Self.mappingJSON(enabled: false)) }
    }

    /// The system turns the tap off on timeout or user input, and the Caps Lock release can be lost meanwhile,
    /// so the held state starts over.
    func reenable() {
        hyperHeld = false; hyperUsed = false
        if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
    }

    private static func hidutil(_ json: String) {
        _ = ProcessRunner.run("/usr/bin/hidutil", ["property", "--set", json], timeout: 5)
    }
}
