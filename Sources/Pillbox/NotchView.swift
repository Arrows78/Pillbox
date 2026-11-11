import SwiftUI

/// Tells the window controller whether the collapsed pill has live content on its sides.
@MainActor
final class LiveState {
    static let shared = LiveState()
    static var lottiePath: String? { UserDefaults.standard.string(forKey: "lottiePath").flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil } }

    /// Whether anything live takes a wing of the collapsed pill. The one predicate for the root view's wings and for the window size.
    static var hasLiveContent: Bool {
        let w = WingLayout.live(left: Preferences.wingLeft.value, right: Preferences.wingRight.value)
        return w.left != nil || w.right != nil
    }

    /// Whether the collapsed pill has wings: live content, or the resting content that fills an otherwise empty pill.
    var hasWings: Bool { Self.hasLiveContent || IdlePill.restingContent }
}

struct NotchRootView: View {
    @ObservedObject var model = NotchModel.shared
    @ObservedObject var timer = TimerService.shared
    @ObservedObject var music = MusicService.shared
    @ObservedObject var caffeine = CaffeineService.shared
    @ObservedObject var privacy = PrivacyService.shared
    @ObservedObject var cleaning = CleaningLock.shared
    @ObservedObject var calls = CallMonitor.shared
    @ObservedObject var downloads = DownloadProgress.shared
    @ObservedObject var build = BuildWatcher.shared
    @ObservedObject var recorder = ScreenRecorder.shared
    @ObservedObject var dictation = DictationService.shared
    @ObservedObject var stocks = StocksService.shared
    @ObservedObject var calendar = CalendarService.shared
    @ObservedObject var weather = WeatherService.shared
    @AppStorage(IdlePill.key) private var idleClock = false
    @AppStorage(Preferences.wingLeft.key) private var wingLeft = Preferences.wingLeft.defaultValue
    @AppStorage(Preferences.wingRight.key) private var wingRight = Preferences.wingRight.defaultValue
    @AppStorage(Preferences.restingLeft.key) private var restingLeft = Preferences.restingLeft.defaultValue
    @AppStorage(Preferences.restingRight.key) private var restingRight = Preferences.restingRight.defaultValue

    /// The wings while something is live; the resting content only fills an otherwise empty pill.
    private var live: (left: WingItem?, right: WingItem?) { WingLayout.live(left: wingLeft, right: wingRight) }
    private var liveWings: Bool { live.left != nil || live.right != nil }
    private var resting: (left: WingItem?, right: WingItem?) { WingLayout.resting(left: restingLeft, right: restingRight) }
    private var restingWings: Bool { idleClock && (resting.left != nil || resting.right != nil) }
    private var wings: Bool { liveWings || restingWings }
    private var size: CGSize { model.size(hasWings: wings) }

    var body: some View {
        ZStack(alignment: .top) {
            IslandBackground(expanded: model.expanded)
            Group {
                if let a = model.approval { ApprovalView(approval: a) }
                else if model.expanded {
                    // Laid out at its base size, then scaled: the panel keeps its proportions at any size.
                    let base = model.panelSize.size
                    ExpandedView().frame(width: base.width, height: base.height).scaleEffect(NotchModel.scale, anchor: .top)
                        .frame(width: size.width, height: size.height, alignment: .top)
                }
                else if dictation.active { DictationView() }
                else if let a = model.activity { ActivityView(activity: a) }
                else if liveWings { WingRow(left: live.left, right: live.right) }
                else if restingWings { WingRow(left: resting.left, right: resting.right, resting: true) }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28))
        }
        .frame(width: size.width, height: size.height)
        .overlay { if !model.expanded && model.activity == nil && model.approval == nil && !dictation.active { PillGestures() } }
        .overlay(alignment: .bottom) {
            if model.dropTargeted && model.expanded {
                RoundedRectangle(cornerRadius: 22).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(8)
            }
        }
        .frame(width: NotchModel.windowSize.width, height: NotchModel.windowSize.height, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: size)
        .onChange(of: wings) { _, _ in NotificationCenter.default.post(name: .notchStateChanged, object: nil) }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }
}

struct Equalizer: View {
    @ObservedObject var spectrum = AudioSpectrum.shared

    /// Height of one bar: the real level when the live spectrum is on, a gentle wave otherwise.
    /// (Kept out of the view body with explicit types: older compilers cannot type-check the mixed expression.)
    static func barHeight(index i: Int, time t: Double, levels: [Float]?) -> CGFloat {
        if let levels, !levels.isEmpty {
            let level: Float = levels[min(i + 1, levels.count - 1)]
            return 3 + 13 * CGFloat(level)
        }
        let wave: Double = abs(sin(t * 4 + Double(i) * 1.3))
        return 5 + 11 * CGFloat(wave)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { ctx in
            let t: Double = ctx.date.timeIntervalSinceReferenceDate
            let levels: [Float]? = spectrum.running ? spectrum.bands : nil
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(.white).frame(width: 3, height: Self.barHeight(index: i, time: t, levels: levels))
                }
            }.frame(height: 16).accessibilityHidden(true)
        }
    }
}

struct ActivityView: View {
    let activity: Activity
    @ObservedObject var model = NotchModel.shared

    var body: some View {
        HStack(spacing: 10) {
            if let cg = activity.image?.cgImage(forProposedRect: nil, context: nil, hints: nil) { Image(decorative: cg, scale: 2).resizable().frame(width: 24, height: 24) }
            else { Image(systemName: activity.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(activity.tint) }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: activity.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let s = activity.subtitle { Text(LocalizedStringKey(s)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
            if let p = activity.progress, Preferences.hudStyle.value == "circle" {
                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 4)
                    Circle().trim(from: 0, to: min(max(p, 0), 1)).stroke(activity.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(Int(min(max(p, 0), 1) * 100))").font(.system(size: 9, weight: .semibold, design: .rounded))
                }.frame(width: 34, height: 34)
            } else if let p = activity.progress {
                Capsule().fill(.white.opacity(0.2)).frame(width: 90, height: 5)
                    .overlay(alignment: .leading) { Capsule().fill(activity.tint).frame(width: 90 * min(max(p, 0), 1)) }
            }
            if let t = activity.actionTitle {
                Button(LocalizedStringKey(t)) { activity.action?(); model.dismissActivity() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, model.geometry.height)
        .padding(.bottom, 4)
        .foregroundStyle(.white)
        .onTapGesture { model.dismissActivity() }
    }
}

struct TabContent: View {
    let tab: Tab
    var body: some View {
        switch tab {
        case .home: HomeTab()
        case .music: MusicTab()
        case .timer: TimerTab()
        case .stocks: StocksTab()
        case .ai: AIUsageTab()
        case .pulls: PullRequestsTab()
        case .reminders: RemindersTab()
        case .notifications: NotificationsTab()
        case .notes: NotesTab()
        case .clipboard: ClipboardTab()
        case .shelf: ShelfTab()
        case .launcher: LauncherTab()
        case .terminal: TerminalTab().clipShape(RoundedRectangle(cornerRadius: 8))
        case .prompter: PrompterTab()
        case .calendar: CalendarTab()
        }
    }
}

struct ExpandedView: View {
    @ObservedObject var model = NotchModel.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TabStrip()
                RecordingStopButton()
                Menu {
                    let current = AudioControl.currentOutput()
                    ForEach(AudioControl.outputDevices()) { d in
                        Button { AudioControl.shared.selectOutput(d) } label: { Text(verbatim: (d.id == current ? "✓ " : "") + d.name) }
                    }
                } label: { Image(systemName: "hifispeaker.fill").foregroundStyle(.white.opacity(0.5)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().hoverTip(localized("Sound output")).accessibilityLabel("Sound output")
                Button { SettingsWindow.show() } label: { Image(systemName: "gearshape.fill").foregroundStyle(.white.opacity(0.5)) }.hoverTip(localized("Settings")).accessibilityLabel("Settings")
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, model.geometry.notch ? model.geometry.height + 6 : max(model.geometry.height - 6, 8))
            .padding(.bottom, 8)
            .zIndex(1)

            Rectangle().fill(Design.hairline).frame(height: 0.5).padding(.horizontal, 22)

            TabContent(tab: model.tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 16)
            .transition(.opacity)
        }
        .foregroundStyle(.white)
        .onChange(of: model.tab) { _, new in model.pinnedOpen = new == .terminal }
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted) { providers in
            model.tab = .shelf
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { MainActor.assumeIsolated { ShelfService.shared.add([url]) } } }
                }
            }
            return true
        }
    }
}

struct ApprovalView: View {
    let approval: Approval
    @ObservedObject var model = NotchModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                Text(verbatim: approval.title).font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            Text(approval.detail).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.8))
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                .padding(6).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button("Ask in terminal") { model.resolveApproval("ask") }
                Spacer()
                Button("Deny") { model.resolveApproval("deny") }.tint(.red)
                Button("Allow") { model.resolveApproval("allow") }.buttonStyle(.borderedProminent).tint(.green)
                    .keyboardShortcut(.return, modifiers: [])
            }.controlSize(.small)
        }
        .padding(.horizontal, 20).padding(.top, model.geometry.height).padding(.bottom, 8)
        .foregroundStyle(.white)
    }
}
