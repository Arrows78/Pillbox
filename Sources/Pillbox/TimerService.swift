import AppKit

@MainActor
final class TimerService: ObservableObject {
    static let shared = TimerService()

    enum Mode: String, CaseIterable, Identifiable {
        case focus = "Focus", rest = "Break", countdown = "Countdown", stopwatch = "Stopwatch"
        var id: String { rawValue }
        /// One-click lengths in minutes, shown as capsules.
        var presets: [Int] {
            switch self {
            case .focus: [15, 25, 45, 60]
            case .rest: [5, 10, 15]
            case .countdown: [1, 3, 5, 10, 30]
            case .stopwatch: []
            }
        }
    }

    @Published var mode: Mode = .focus { didSet { if oldValue != mode { reset() } } }
    @Published private(set) var running = false
    @Published private(set) var now = Date()
    @Published var label = ""
    @Published var focusMinutes = 25 { didSet { if mode == .focus && !running { reset() } } }
    @Published var breakMinutes = 5 { didSet { if mode == .rest && !running { reset() } } }
    @Published var countdownMinutes = 10 { didSet { if mode == .countdown && !running { reset() } } }
    @Published var chain = true
    @Published var sessions: [String: Int] = Store.load("sessions.json", as: [String: Int].self) ?? [:]

    private var endDate: Date?
    private var startDate: Date?
    private var accumulated: TimeInterval = 0   // stopwatch time before the current run
    private var pausedRemaining: TimeInterval?
    private var timer: Timer?

    var total: TimeInterval {
        switch mode {
        case .focus: Double(focusMinutes * 60)
        case .rest: Double(breakMinutes * 60)
        case .countdown: Double(countdownMinutes * 60)
        case .stopwatch: 0
        }
    }

    /// Seconds shown on screen (remaining for countdowns, elapsed for the stopwatch). Wall-clock based, so it never drifts.
    var seconds: TimeInterval {
        if mode == .stopwatch { return accumulated + (running ? now.timeIntervalSince(startDate ?? now) : 0) }
        if running, let e = endDate { return max(0, e.timeIntervalSince(now)) }
        return pausedRemaining ?? total
    }

    var progress: Double { mode == .stopwatch || total == 0 ? 0 : 1 - seconds / total }
    var isActive: Bool { running || (pausedRemaining != nil && pausedRemaining != total) || (mode == .stopwatch && accumulated > 0) }

    var display: String { Self.format(seconds) }
    static func format(_ s: TimeInterval) -> String {
        let t = Int(s.rounded(.down)); let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    func toggle() { running ? pause() : start() }

    func start() {
        guard !running else { return }
        now = Date()
        if mode == .stopwatch { startDate = now } else { endDate = now.addingTimeInterval(pausedRemaining ?? total) }
        running = true
        if mode == .focus { AmbientNoise.shared.autoStart() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func pause() {
        guard running else { return }
        // The last tick may be up to 0.25 s old: read the clock now, so the pause keeps the exact time.
        now = Date()
        if mode == .stopwatch { accumulated = seconds } else { pausedRemaining = seconds }
        running = false; timer?.invalidate()
        AmbientNoise.shared.autoStop()
    }

    func reset() {
        running = false; timer?.invalidate()
        AmbientNoise.shared.autoStop()
        endDate = nil; startDate = nil; accumulated = 0; pausedRemaining = nil
        objectWillChange.send()
    }

    private func tick() {
        now = Date()
        guard mode != .stopwatch, let e = endDate, now >= e else { return }
        finish()
    }

    private func finish() {
        let finished = mode
        reset()
        NSSound(named: "Glass")?.play()
        if finished == .focus {
            let k = Self.dayKey(Date()); sessions[k, default: 0] += 1; Store.save(sessions, "sessions.json")
        }
        NotchModel.shared.show(Activity(symbol: finished == .focus ? "checkmark.circle.fill" : "bell.fill",
                                        title: finished == .focus ? localized("Focus session done") : localized("%@ finished", localized(finished.rawValue)),
                                        subtitle: label.isEmpty ? nil : label, tint: .green, duration: 5))
        if chain && finished == .focus { mode = .rest; start() }
        else if chain && finished == .rest { mode = .focus; start() }
    }

    func repeatTimer() { reset(); start() }

    nonisolated static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f
    }()

    /// Focus sessions per day for the last 7 days (oldest first).
    var week: [(label: String, count: Int)] {
        (0..<7).reversed().map { off in
            let d = Calendar.current.date(byAdding: .day, value: -off, to: Date())!
            return (Self.weekdayFormatter.string(from: d), sessions[Self.dayKey(d)] ?? 0)
        }
    }

    var streak: Int {
        var n = 0; var d = Date()
        if (sessions[Self.dayKey(d)] ?? 0) == 0 { d = Calendar.current.date(byAdding: .day, value: -1, to: d)! }
        while (sessions[Self.dayKey(d)] ?? 0) > 0 { n += 1; d = Calendar.current.date(byAdding: .day, value: -1, to: d)! }
        return n
    }
}
