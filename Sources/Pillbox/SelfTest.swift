import AppKit
import SwiftUI
import SQLite3
import AVFoundation
import PDFKit
import ImageIO

/// Non-interactive checks behind `--selftest` (no window, no permission, no network).
/// The checks live in SelfTest+<Area>.swift; run() keeps their order.
@MainActor
enum SelfTest {
    static var failures = 0

    static func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        print("\(ok ? "PASS" : "FAIL")  \(name)\(ok ? "" : "  \(detail())")")
        if !ok { failures += 1 }
    }

    static func run() -> Int32 {
        lyrics(); math(); formatting(); clipboard(); stocks(); snapping(); weather(); timer(); usage(); geometry(); stores(); settingsRouter(); settingsSearch(); statusMenu(); islandHistory(); homeLayout(); tabOrder(); musicEvents(); permissionGroups(); lottieSpeedDefault(); launchOptions(); notificationSearch(); paneReset(); storeSchema(); powerGate(); dataBackup(); shelfCopyFile(); shelf(); palette(); snippets(); watchers(); converter(); reminders()
        shortcutsAndSearch(); networkAndAudioDevices(); teleprompterAndPrompterVoice(); tabBar(); prompterSpeeds(); teleprompterEnd()
        hyperKeyAndMenuBar(); focusCallsAndNotifications(); screenAskAndKeychain(); spectrum(); gesturesAndWorldClock()
        shakeAndBreaks(); downloadsAndBuild(); bluetoothBatteries(); quickCapture(); displayOptions()
        activityQueue(); activityTitleDisplay(); shellActions(); notificationFeed(); pillAndTheme()
        usageAlert(); githubPRs(); edgeBar()
        mcpProtocol(); agentActions(); turnTokens(); panelSize(); tabPanelSizes(); playerAndLyrics(); terminalEnvironment(); terminalLook(); equalizer(); copyStackAndHistory()
        paletteMath(); paletteSources(); settingsBackup(); updateVersions(); shortcutsAndDiagnostics()
        awareness(); recordingQRAnnotate(); dictationAndActivity()
        appVolume()
        battery()
        tabsAndQueue(); calendarFeeds(); videoSpeedAndWindowDrag(); externalBrightness(); equalizerAndLyricStamps(); appEqualizerAndBoost(); extraBrightness(); windowGeometry()
        aiUsage(); annotateSteps(); notificationApps(); copilotQuota(); verificationCodes(); updater(); brewCheck(); clipboardImport(); clipboardPrivacy(); typingSounds(); ambientNoise(); idleCollapse()
        calendarWeek()
        agentApprovals()
        islandTable()
        pillWings()
        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
        return failures == 0 ? 0 : 1
    }

    /// Runs an async operation to completion while keeping the main run loop alive.
    static func wait<T>(_ op: @escaping () async throws -> T) -> Result<T, Error> {
        var result: Result<T, Error>?
        Task { @MainActor in do { result = .success(try await op()) } catch { result = .failure(error) } }
        let deadline = Date().addingTimeInterval(30)
        while result == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        return result ?? .failure(ConvertError.failed("timeout"))
    }
}

/// `--render <dir>` draws the island states to PNG from an offscreen window: no permission needed.
@MainActor
enum ViewRenderer {
    static func run(into dir: String) -> Int32 {
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let model = NotchModel.shared
        model.geometry = NotchGeometry(width: 185, height: 32, screen: nil)
        var ok = true
        func save<V: View>(_ name: String, _ view: V, size: CGSize) {
            let framed = view.frame(width: size.width, height: size.height, alignment: .top)
                .background(Color(white: 0.45)).environment(\.colorScheme, .dark)
            // Drawn by a real hosting view in an offscreen window: AppKit-backed controls (fields, menus) render too.
            let host = NSHostingView(rootView: framed)
            let win = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size), styleMask: .borderless, backing: .buffered, defer: false)
            win.contentView = host; win.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("FAIL  render \(name)"); ok = false; return }
            host.cacheDisplay(in: host.bounds, to: rep); win.orderOut(nil)
            guard let png = rep.representation(using: .png, properties: [:]) else { print("FAIL  render \(name)"); ok = false; return }
            try? png.write(to: out.appendingPathComponent(name + ".png")); print("wrote \(name).png")
        }
        func island<V: View>(_ v: V, _ size: CGSize) -> some View {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28).fill(.black)
                v.foregroundStyle(.white)
            }.frame(width: size.width, height: size.height)
        }
        // Drawn under a real 32 pt notch, so the header takes the room it takes on a MacBook.
        model.geometry = NotchGeometry(width: 185, height: 32, notch: true)
        for tab in Tab.allCases where tab != .terminal {
            model.tab = tab; model.expanded = true
            model.panelSize = PanelSize.of(tab)
            let size = model.panelSize.size
            save("tab-\(tab.rawValue)", island(ExpandedView(), size), size: size)
        }
        let mixer = AppVolumeService.shared
        mixer.preview = true
        mixer.apps = [AppAudio(id: "com.spotify.client", name: "Spotify", icon: nil, processes: [], playing: true),
                      AppAudio(id: "com.google.Chrome", name: "Google Chrome with a long name", icon: nil, processes: [], playing: true),
                      AppAudio(id: "com.apple.Safari", name: "Safari", icon: nil, processes: [], playing: true),
                      AppAudio(id: "us.zoom.xos", name: "zoom.us", icon: nil, processes: [], playing: true)]
        mixer.showing = true; model.tab = .music
        save("tab-music-mixer", island(ExpandedView(), NotchModel.expandedSize), size: NotchModel.expandedSize)
        mixer.showing = false; mixer.apps = []; mixer.preview = false
        model.expanded = false
        let acts = [Activity(symbol: "hammer.fill", title: "Build done", subtitle: "main passed in 42s", tint: .green),
                    Activity(symbol: "speaker.wave.2.fill", title: "Volume", progress: 0.6),
                    Activity(symbol: "arrow.down.circle.fill", title: "Download finished", subtitle: "report.pdf", tint: .blue, actionTitle: "Reveal")]
        for (i, a) in acts.enumerated() {
            let size = CGSize(width: 330, height: 66)
            save("activity-\(i)", island(ActivityView(activity: a), size), size: size)
        }
        ScreenRecorder.shared.since = Date(timeIntervalSinceNow: -75)
        save("recording-wings", island(WingRow(left: .recording, right: .recording), model.size(hasWings: true)), size: model.size(hasWings: true))
        model.tab = .shelf; model.expanded = true
        save("recording-panel", island(ExpandedView(), NotchModel.expandedSize), size: NotchModel.expandedSize)
        model.expanded = false; ScreenRecorder.shared.since = nil
        let qr = Activity(symbol: "qrcode", title: "QR code link", subtitle: "https://example.com/a%20b?q=1", tint: .green, actionTitle: "Open link")
        save("activity-qr", island(ActivityView(activity: qr), CGSize(width: 330, height: 66)), size: CGSize(width: 330, height: 66))
        let hist = (0..<288).map { i in BatterySample(t: Date().addingTimeInterval(Double(i - 287) * 300), level: 20 + abs(i % 120 - 60), charging: i % 120 > 100) }
        let gaugeArea = CGSize(width: 280, height: 76)   // the gauge row it replaces on Home
        save("battery-chart", island(BatteryChartCard(samples: hist, level: 64, remaining: "3:20", health: (92, 312)), gaugeArea), size: gaugeArea)
        let net = (0..<300).map { i in NetSample(t: Date().addingTimeInterval(Double(i - 299) * 2), down: abs(sin(Double(i) / 9)) * 2e6, up: abs(cos(Double(i) / 13)) * 4e5) }
        save("network-sparkline", VStack(alignment: .leading) {   // the 190 pt left column of Home, typical and worst case
            NetworkLine(down: 1_500_000, up: 512, samples: net); NetworkLine(down: 999_900_000, up: 999_900_000, samples: net)
        }.frame(width: 190, alignment: .leading).background(.black), size: CGSize(width: 190, height: 34))
        save("battery-chart-empty", island(BatteryChartCard(samples: [], level: 100, health: nil, hasBattery: false), gaugeArea), size: gaugeArea)
        save("snapzones", SnapZonesView(), size: SnapZones.panelSize)
        save("widgets", DesktopWidgetView(), size: CGSize(width: 330, height: 190))
        let appr = Approval(tool: "Bash", detail: "rm -rf ./build && swift build", respond: { _ in })
        save("approval", island(ApprovalView(approval: appr), CGSize(width: 520, height: 124)), size: CGSize(width: 520, height: 124))
        let aw = [Activity(symbol: SpaceWatcher.symbol, title: localized("Desktop %d", 3), tint: .cyan),
                  Activity(symbol: "hand.raised.fill", title: localized("Blocked while focusing"), subtitle: "Discord", tint: .orange, image: BlockedAppsStore.bitmap(NSWorkspace.shared.icon(forFile: "/System/Applications/Messages.app")), actionTitle: localized("Allow 5 min")),
                  Activity(symbol: "video.fill", title: localized("Camera turned on"), subtitle: localized("Probably %@", "Microsoft Teams (work or school)"), tint: .green)]
        for (i, a) in aw.enumerated() { save("awareness-\(i)", island(ActivityView(activity: a), CGSize(width: 330, height: 66)), size: CGSize(width: 330, height: 66)) }
        let dic = DictationService.shared
        dic.text = DictationText(); dic.forceActive(true)
        let dsize = model.size(hasWings: false)
        save("dictation-empty", island(DictationView(), dsize), size: dsize)
        dic.text.update("Remind me to send the quarterly report to the whole team before Friday noon", finished: false)
        dic.meter.level = 0.7
        save("dictation-text", island(DictationView(), dsize), size: dsize)
        dic.forceActive(false)
        var demo = ActivityLog()
        for (i, n) in [3200, 5400, 800, 0, 6100, 4700, 2900].enumerated() {
            demo.add(keys: n, clicks: n / 6, metres: Double(n) / 20, on: Calendar.current.date(byAdding: .day, value: i - 6, to: Date())!)
        }
        ActivityCounter.shared.preview(demo)
        for (i, a) in [Activity(symbol: "chart.bar.fill", title: localized("%@ keys · %@ clicks", 12_345.formatted(), 2_345.formatted()), subtitle: localized("%@ of mouse travel", ActivityCounter.distance(1234)), tint: .cyan),
                       Activity(symbol: "chart.bar.fill", title: "Activity counter is off", tint: .orange, actionTitle: "Turn on"),
                       Activity(symbol: "mic.slash.fill", title: "Microphone needed", subtitle: "Also allow speech recognition", tint: .orange, actionTitle: "Settings")].enumerated() {
            let size = CGSize(width: 330, height: 66)
            save("activity-today-\(i)", island(ActivityView(activity: a), size), size: size)
        }
        save("activity-card", ActivityCounterCard().background(Color(white: 0.12)), size: CGSize(width: 530, height: 90))
        return ok ? 0 : 1
    }
}
