import SwiftUI

/// Tells the window controller whether the collapsed pill has live content on its sides.
@MainActor
final class LiveState {
    static let shared = LiveState()
    var hasWings: Bool {
        let t = TimerService.shared, m = MusicService.shared
        return t.isActive || CaffeineService.shared.active || (m.hasTrack && m.isPlaying) || PrivacyService.shared.live || CleaningLock.shared.active
    }
}

struct NotchRootView: View {
    @ObservedObject var model = NotchModel.shared
    @ObservedObject var timer = TimerService.shared
    @ObservedObject var music = MusicService.shared
    @ObservedObject var caffeine = CaffeineService.shared
    @ObservedObject var privacy = PrivacyService.shared
    @ObservedObject var cleaning = CleaningLock.shared

    private var wings: Bool { timer.isActive || caffeine.active || (music.hasTrack && music.isPlaying) || privacy.live || cleaning.active }
    private var size: CGSize { model.size(hasWings: wings) }

    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: model.expanded ? 28 : 12, bottomTrailingRadius: model.expanded ? 28 : 12)
                .fill(.black)
            Group {
                if let a = model.approval { ApprovalView(approval: a) }
                else if model.expanded { ExpandedView() }
                else if let a = model.activity { ActivityView(activity: a) }
                else if wings { CollapsedWings() }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28))
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .bottom) {
            if model.dropTargeted && model.expanded {
                RoundedRectangle(cornerRadius: 22).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(8)
            }
        }
        .frame(width: NotchModel.windowSize.width, height: NotchModel.windowSize.height, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: size)
        .onChange(of: wings) { _ in NotificationCenter.default.post(name: .notchStateChanged, object: nil) }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }
}

struct CollapsedWings: View {
    @ObservedObject var cleaning = CleaningLock.shared
    @ObservedObject var privacy = PrivacyService.shared
    @ObservedObject var model = NotchModel.shared
    @ObservedObject var timer = TimerService.shared
    @ObservedObject var music = MusicService.shared
    @ObservedObject var caffeine = CaffeineService.shared

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: NotchModel.wing, alignment: .center)
            Spacer(minLength: model.geometry.width)
            right.frame(width: NotchModel.wing, alignment: .center)
        }
        .frame(maxHeight: model.geometry.height)
    }

    @ViewBuilder private var left: some View {
        if CleaningLock.shared.active {
            Image(systemName: "lock.fill").foregroundStyle(.yellow)
        } else if privacy.live {
            HStack(spacing: 4) {
                if privacy.micLive { Image(systemName: "mic.fill").foregroundStyle(.orange) }
                if privacy.cameraLive { Image(systemName: "video.fill").foregroundStyle(.green) }
            }.font(.system(size: 11))
        } else if music.hasTrack && music.isPlaying, let art = music.artwork {
            Image(nsImage: art).resizable().frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 5))
        } else if timer.isActive {
            Image(systemName: "timer").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
        } else if caffeine.active {
            Image(systemName: "cup.and.saucer.fill").font(.system(size: 13)).foregroundStyle(.orange)
        } else if music.hasTrack && music.isPlaying {
            Image(systemName: "music.note").foregroundStyle(.white)
        }
    }

    @ViewBuilder private var right: some View {
        if CleaningLock.shared.active {
            Text("\(CleaningLock.shared.remaining)s").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.yellow)
        } else if timer.isActive {
            Text(timer.display).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.orange)
        } else if music.hasTrack && music.isPlaying {
            Equalizer()
        } else if let sym = StocksService.shared.pinned, let q = StocksService.shared.quotes[sym] {
            Text(String(format: "%@%.1f%%", q.change >= 0 ? "+" : "", q.change * 100))
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(q.change >= 0 ? .green : .red)
        } else if caffeine.active, let u = caffeine.until {
            Text(u, style: .timer).font(.system(size: 10, design: .monospaced)).foregroundStyle(.orange)
        }
    }
}

struct Equalizer: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(.white).frame(width: 3, height: 5 + 11 * abs(sin(t * 4 + Double(i) * 1.3)))
                }
            }.frame(height: 16)
        }
    }
}

struct ActivityView: View {
    let activity: Activity
    @ObservedObject var model = NotchModel.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: activity.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(activity.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(activity.title)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let s = activity.subtitle { Text(LocalizedStringKey(s)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
            if let p = activity.progress {
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

struct ExpandedView: View {
    @ObservedObject var model = NotchModel.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Tab.allCases) { tab in
                    Button { withAnimation(.easeOut(duration: 0.15)) { model.tab = tab } } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, height: 24)
                            .background(model.tab == tab ? Color.white.opacity(0.18) : .clear, in: Capsule())
                            .foregroundStyle(model.tab == tab ? .white : .white.opacity(0.5))
                    }.buttonStyle(.plain).help(tab.title)
                }
                Spacer()
                Button { SettingsWindow.show() } label: { Image(systemName: "gearshape.fill").foregroundStyle(.white.opacity(0.5)) }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, max(model.geometry.height - 6, 8))
            .padding(.bottom, 6)

            Group {
                switch model.tab {
                case .home: HomeTab()
                case .music: MusicTab()
                case .timer: TimerTab()
                case .stocks: StocksTab()
                case .ai: AIUsageTab()
                case .notes: NotesTab()
                case .clipboard: ClipboardTab()
                case .shelf: ShelfTab()
                case .launcher: LauncherTab()
                case .terminal: TerminalTab().clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
            .transition(.opacity)
        }
        .foregroundStyle(.white)
        .onChange(of: model.tab) { model.pinnedOpen = $0 == .terminal }
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
                Text("\(approval.tool) wants to run").font(.system(size: 13, weight: .semibold))
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
