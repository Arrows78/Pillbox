import AppKit

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--selftest") {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pillbox-data-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        setenv("PILLBOX_DATA_DIR", dir.path, 1)
        let code = SelfTest.run()
        try? FileManager.default.removeItem(at: dir)
        exit(code)
    }
    if let i = CommandLine.arguments.firstIndex(of: "--render"), CommandLine.arguments.indices.contains(i + 1) {
        exit(ViewRenderer.run(into: CommandLine.arguments[i + 1]))
    }
    if CommandLine.arguments.contains("--usage") {   // prints the AI usage scan and how long it took
        for scan in [{ AIUsageService.scanClaude() }, { AIUsageService.scanCodex() }] {
            let t = Date(); let u = scan()
            print(String(format: "%@: 5h %d, today %d, 7d %d, cache %d, limit %@  (%.2fs)", u.name, u.fiveHour, u.today, u.week, u.cacheRead,
                         u.limitPercent.map { String(format: "%.0f%%", $0) } ?? "-", Date().timeIntervalSince(t)))
        }
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
