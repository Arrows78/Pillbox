import AppKit
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("hoverOpen") private var hoverOpen = true
    @AppStorage("hoverDelay") private var hoverDelay = 0.12
    @AppStorage("capsHUD") private var capsHUD = true
    @AppStorage("downloadAlerts") private var downloadAlerts = true
    @AppStorage("privacyIndicator") private var privacyIndicator = true
    @AppStorage("volumeHUD") private var volumeHUD = true
    @AppStorage("fullChargeLevel") private var fullCharge = 100
    @AppStorage("pillWidth") private var pillWidth = 170.0
    @AppStorage("devAPIEnabled") private var devAPI = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var copied = false

    var body: some View {
        Form {
            PermissionsSection()
            Section("General") {
                Toggle("Open when hovering the notch", isOn: $hoverOpen)
                if hoverOpen { Slider(value: $hoverDelay, in: 0.05...0.6) { Text("Hover delay") } }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
                if NotchModel.shared.geometry.screen?.safeAreaInsets.top == 0 {
                    Slider(value: $pillWidth, in: 120...260) { Text("Pill width") }
                }
            }
            Section("Alerts") {
                Toggle("Caps Lock island", isOn: $capsHUD)
                Toggle("Download finished island", isOn: $downloadAlerts)
                Toggle("Microphone and camera indicator", isOn: $privacyIndicator)
                Toggle("Volume island", isOn: $volumeHUD)
                Stepper("Charged island at \(fullCharge)%", value: $fullCharge, in: 80...100, step: 5)
            }
            Section("Developer API (127.0.0.1:\(DevAPI.defaultPort))") {
                Toggle("Enable local API", isOn: $devAPI).onChange(of: devAPI) { _ in DevAPI.shared.apply() }
                if devAPI {
                    Button("Copy Claude Code approval hook") {
                        let path = Bundle.main.path(forResource: "claude-hook", ofType: "sh") ?? "/path/to/Pillbox/scripts/claude-hook.sh"
                        let cfg = "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Bash|Write|Edit\",\"hooks\":[{\"type\":\"command\",\"command\":\"\(path)\",\"timeout\":130}]}]}}"
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(cfg, forType: .string)
                    }
                    Button(copied ? "Copied" : "Copy example request") {
                        let cmd = "curl -X POST http://127.0.0.1:\(DevAPI.defaultPort)/notify -H 'Authorization: Bearer \(DevAPI.token)' -d '{\"title\":\"Build done\",\"symbol\":\"hammer.fill\"}'"
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(cmd, forType: .string); copied = true
                    }
                }
            }
            Section("Shortcuts") {
                Text("⌃⌥K  command palette    ⌃⌥N  toggle notch").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).frame(width: 480, height: 640)
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Pillbox Settings"; w.styleMask = [.titled, .closable]; w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center(); window?.makeKeyAndOrderFront(nil)
    }
}
