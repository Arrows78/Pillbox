import AppKit

// MARK: The system equalizer switch and gains

/// Keeps the system equalizer in line with its settings: starts or stops it with the switch, applies the three
/// bands live, and follows the output device when it changes.
/// Settings keys of the equalizer, outside the macOS 14.2 check so the settings window can bind them.
enum EqualizerKeys {
    static let key = "systemEQ", bassKey = "eqBass", midKey = "eqMid", trebleKey = "eqTreble"
}

@available(macOS 14.2, *)
@MainActor
final class EqualizerService {
    static let shared = EqualizerService()
    private let eq = SystemEQ()

    /// The three gains in dB, each between -12 and 12, read from the settings.
    static func gains() -> (bass: Double, mid: Double, treble: Double) {
        let d = UserDefaults.standard
        func band(_ key: String) -> Double { min(max(d.object(forKey: key) as? Double ?? 0, -12), 12) }
        return (band(EqualizerKeys.bassKey), band(EqualizerKeys.midKey), band(EqualizerKeys.trebleKey))
    }

    func apply() {
        guard UserDefaults.standard.bool(forKey: EqualizerKeys.key) else {
            eq.stop()
            return
        }
        let g = Self.gains()
        if eq.running {
            eq.setGains(bassDB: g.bass, midDB: g.mid, trebleDB: g.treble)
            return
        }
        do {
            try eq.start(bassDB: g.bass, midDB: g.mid, trebleDB: g.treble)
            eq.onOutputChange = { [weak self] in
                MainActor.assumeIsolated { self?.restart() }
            }
        } catch {
            // Usually the System Audio Recording permission is missing: say so, and leave the switch off.
            UserDefaults.standard.set(false, forKey: EqualizerKeys.key)
            NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: L("The equalizer could not start"), subtitle: L("Allow System Audio Recording for Pillbox."), tint: .orange, duration: 5))
        }
    }

    /// The output changed (headphones plugged in, for example): rebuild the tap on the new device.
    private func restart() {
        guard eq.running else { return }
        eq.stop()
        apply()
    }
}
