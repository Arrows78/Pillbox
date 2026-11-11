import Foundation
import AppKit
import IOKit.pwr_mgt
import IOKit.ps
import EventKit
import SwiftUI

@MainActor
final class CaffeineService: ObservableObject {
    static let shared = CaffeineService()
    @Published private(set) var active = false
    @Published private(set) var until: Date?
    private var assertion: IOPMAssertionID = 0
    private var timer: Timer?

    /// `minutes == nil` keeps the Mac awake until turned off.
    func start(minutes: Int? = nil) {
        stop(silently: true)
        let status = IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Pillbox keep awake" as CFString, &assertion)
        guard status == kIOReturnSuccess else { return }
        active = true
        if let m = minutes {
            until = Date().addingTimeInterval(Double(m) * 60)
            timer = Timer.scheduledTimer(withTimeInterval: Double(m) * 60, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
        }
        NotchModel.shared.show(Activity(symbol: "cup.and.saucer.fill", title: localized("Keep awake on"),
                                        subtitle: minutes.map { localized("for %d min", $0) } ?? localized("until turned off"), tint: .orange))
    }

    func stop(silently: Bool = false) {
        guard active else { return }
        IOPMAssertionRelease(assertion); assertion = 0
        timer?.invalidate(); active = false; until = nil
        if !silently { NotchModel.shared.show(Activity(symbol: "cup.and.saucer", title: localized("Keep awake off"))) }
    }

    func toggle() { active ? stop() : start() }

    /// Keeps the Mac awake until the next occurrence of a clock time (today, or tomorrow if already past).
    func start(until hour: Int, minute: Int = 0, now: Date = Date()) {
        guard let target = Calendar.current.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime) else { return }
        start(minutes: max(Int(target.timeIntervalSince(now) / 60), 1))
    }
}

// MARK: Battery
