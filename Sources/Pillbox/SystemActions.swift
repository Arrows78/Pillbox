import Foundation
import AppKit
import IOKit.pwr_mgt
import IOKit.ps
import EventKit
import SwiftUI

@MainActor
enum SystemActions {
    private static var capsMonitor: Any?
    private static var capsLocalMonitor: Any?
    private static var capsOn = NSEvent.modifierFlags.contains(.capsLock)

    static func startCapsLockHUD() {
        capsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { capsChanged($0) }
        // The global monitor does not see events sent to Pillbox's own windows, so the local one covers those.
        capsLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            capsChanged(event)
            return event
        }
    }

    nonisolated private static func capsChanged(_ e: NSEvent) {
        let on = e.modifierFlags.contains(.capsLock)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard on != capsOn else { return }
                capsOn = on
                guard Defaults.bool("capsHUD", default: true) else { return }
                NotchModel.shared.show(Activity(symbol: on ? "capslock.fill" : "capslock", title: on ? localized("Caps Lock on") : localized("Caps Lock off"),
                                                tint: on ? .yellow : .white, duration: 1.5, priority: .low, kind: .capsLock))
            }
        }
    }

    static func pickColor() {
        NSColorSampler().show { color in
            // The sampler reports on the main thread.
            MainActor.assumeIsolated {
                guard let color else { return }
                let hex = color.hexString
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hex, forType: .string)
                NotchModel.shared.show(Activity(symbol: "eyedropper.full", title: hex, subtitle: localized("Copied"), tint: Color(nsColor: color)))
            }
        }
    }

    /// Interactive area capture straight to the clipboard (system `screencapture`).
    static func captureArea() {
        NotchModel.shared.collapse()
        let screencapture = Process()
        screencapture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        screencapture.arguments = ["-i", "-c"]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Cancelling the capture leaves the clipboard as it was, so a change of its count means a new copy.
            let before = NSPasteboard.general.changeCount
            screencapture.terminationHandler = { _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if NSPasteboard.general.changeCount != before, NSImage(pasteboard: .general) != nil {
                            NotchModel.shared.show(Activity(symbol: "camera.viewfinder", title: localized("Screenshot copied"), tint: .green))
                        }
                    }
                }
            }
            do { try screencapture.run() } catch {
                MainActor.assumeIsolated {
                    NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: localized("Could not take the screenshot"), tint: .orange))
                }
            }
        }
    }
}

// MARK: Calendar
