import AppKit
import Combine

/// What the menu bar icon shows. The most urgent state wins: a recording, then a running timer, then a muted
/// microphone, then keep awake; otherwise the plain capsule.
struct StatusIconLook: Equatable {
    let symbol: String
    /// Text next to the symbol, the timer's countdown; empty for none.
    let title: String
    /// Drawn in red rather than as a template, so a recording is seen at a glance.
    let alert: Bool

    static func resolve(recording: Bool, timer: String?, micMuted: Bool, awake: Bool) -> StatusIconLook {
        if recording { return StatusIconLook(symbol: "record.circle.fill", title: "", alert: true) }
        if let timer { return StatusIconLook(symbol: "timer", title: timer, alert: false) }
        if micMuted { return StatusIconLook(symbol: "mic.slash.fill", title: "", alert: false) }
        if awake { return StatusIconLook(symbol: "cup.and.saucer.fill", title: "", alert: false) }
        return StatusIconLook(symbol: "capsule.fill", title: "", alert: false)
    }
}

/// Keeps the status item's icon in step with the live state. It listens to the services that change it rather
/// than polling, and redraws at most twice a second.
@MainActor
final class StatusIcon {
    private weak var button: NSStatusBarButton?
    private var shown: StatusIconLook?
    private var subscription: AnyCancellable?

    init(button: NSStatusBarButton?) {
        self.button = button
        let changes: [AnyPublisher<Void, Never>] = [
            TimerService.shared.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            ScreenRecorder.shared.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            CaffeineService.shared.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            AudioControl.shared.objectWillChange.map { _ in }.eraseToAnyPublisher(),
        ]
        // objectWillChange fires before the value changes: hopping to the next run loop turn reads the new one.
        subscription = Publishers.MergeMany(changes)
            .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] in self?.refresh() }
        refresh()
    }

    func refresh() {
        let timers = TimerService.shared
        let look = StatusIconLook.resolve(recording: ScreenRecorder.shared.recording, timer: timers.isActive ? timers.display : nil,
                                          micMuted: AudioControl.shared.micMuted, awake: CaffeineService.shared.active)
        guard look != shown, let button else { return }
        shown = look
        let image = NSImage(systemSymbolName: look.symbol, accessibilityDescription: "Pillbox")
        image?.isTemplate = !look.alert
        button.image = image
        button.contentTintColor = look.alert ? .systemRed : nil
        button.title = look.title.isEmpty ? "" : " " + look.title
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.imagePosition = look.title.isEmpty ? .imageOnly : .imageLeading
    }
}
