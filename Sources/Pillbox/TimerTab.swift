import AppKit
import Foundation
import SwiftUI

struct TimerTab: View {
    @ObservedObject var service = TimerService.shared

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 7)
                Circle().trim(from: 0, to: service.progress).stroke(Tab.timer.tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90)).shadow(color: .orange.opacity(service.running ? 0.55 : 0), radius: 5)
                VStack(spacing: 0) {
                    if let emoji = Mascot.emoji(for: Mascot.current, progress: service.progress) { Text(emoji).font(.system(size: 20)).scaleEffect(service.running ? 1.08 : 1).animation(service.running ? .easeInOut(duration: 0.8).repeatForever() : .default, value: service.running) }
                    Text(service.display).font(.system(size: 30, weight: .semibold, design: .monospaced))
                    Text(LocalizedStringKey(service.mode.rawValue)).font(Design.caption).foregroundStyle(.secondary)
                }
            }.frame(width: 180, height: 180)

            VStack(alignment: .leading, spacing: 8) {
                PillSegmented(options: TimerService.Mode.allCases, selection: $service.mode, tint: Tab.timer.tint) { LocalizedStringKey($0.rawValue) }
                HStack(spacing: 8) {
                    Button { service.toggle() } label: { Label(LocalizedStringKey(service.running ? "Pause" : "Start"), systemImage: service.running ? "pause.fill" : "play.fill") }
                        .buttonStyle(PillButtonStyle(tint: Tab.timer.tint))
                    Button("Reset") { service.reset() }.buttonStyle(PillButtonStyle())
                    if service.mode == .countdown { Button("Repeat") { service.repeatTimer() }.buttonStyle(PillButtonStyle()) }
                    AmbientMenu()
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Button { stepBinding.wrappedValue = max(1, stepBinding.wrappedValue - 1) } label: { Image(systemName: "minus") }.accessibilityLabel("Fewer minutes")
                        Text("\(stepBinding.wrappedValue) min").font(.system(size: 11, weight: .medium)).monospacedDigit().frame(minWidth: 44)
                        Button { stepBinding.wrappedValue = min(180, stepBinding.wrappedValue + 1) } label: { Image(systemName: "plus") }.accessibilityLabel("More minutes")
                    }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Design.card, in: Capsule())
                    .disabled(service.mode == .stopwatch || service.running).opacity(service.mode == .stopwatch || service.running ? 0.4 : 1)
                }
                HStack(spacing: 6) {
                    ForEach(service.mode.presets, id: \.self) { minutes in
                        let on = stepBinding.wrappedValue == minutes
                        Button { stepBinding.wrappedValue = minutes } label: {
                            Text("\(minutes) min").font(.system(size: 11, weight: .medium)).monospacedDigit()
                                .foregroundStyle(on ? .white : .white.opacity(0.7))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(on ? Tab.timer.tint.opacity(0.35) : Design.card, in: Capsule())
                                .overlay(Capsule().strokeBorder(on ? Tab.timer.tint.opacity(0.7) : Design.hairline, lineWidth: 0.5))
                        }.buttonStyle(.plain).disabled(service.running)
                    }
                    if service.mode == .stopwatch { Text("Counts up until you stop it").font(Design.label).foregroundStyle(Design.secondary) }
                    Spacer(minLength: 0)
                }.opacity(service.running ? 0.6 : 1)
                TextField("Name this timer", text: $service.label).pillField()
                HStack(spacing: 10) {
                    Toggle("Chain", isOn: $service.chain).toggleStyle(.switch).controlSize(.mini).tint(Tab.timer.tint).font(Design.label)
                    Label("\(service.streak) day streak", systemImage: "flame.fill").font(Design.label).foregroundStyle(Tab.timer.tint)
                    Spacer()
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(service.week.enumerated()), id: \.offset) { _, day in
                            Capsule().fill(day.count > 0 ? Tab.timer.tint : .white.opacity(0.15))
                                .frame(width: 5, height: 4 + CGFloat(min(day.count, 6)) * 3)
                        }
                    }.frame(height: 24, alignment: .bottom).hoverTip(localized("Focus sessions, last 7 days"))
                }
            }
        }
    }

    /// The length the stepper and the presets edit: each mode has its own. The stopwatch has no length, so it shows 0 and the stepper is off.
    private var stepBinding: Binding<Int> {
        switch service.mode {
        case .focus: $service.focusMinutes
        case .rest: $service.breakMinutes
        case .countdown: $service.countdownMinutes
        case .stopwatch: .constant(0)
        }
    }
}
