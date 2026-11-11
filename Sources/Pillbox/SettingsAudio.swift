import AppKit
import SwiftUI
import ServiceManagement

/// The Audio and sounds pane: the live spectrum, the system equalizer and the typing and ambient sounds.
struct SettingsAudioPane: View {
    @AppStorage(Preferences.liveSpectrum.key) private var liveSpectrum = Preferences.liveSpectrum.defaultValue
    @AppStorage(Preferences.browserMusic.key) private var browserMusic = Preferences.browserMusic.defaultValue
    @AppStorage(Preferences.systemEQ.key) private var systemEQ = Preferences.systemEQ.defaultValue
    @AppStorage(Preferences.eqBass.key) private var eqBass = Preferences.eqBass.defaultValue
    @AppStorage(Preferences.eqMid.key) private var eqMid = Preferences.eqMid.defaultValue
    @AppStorage(Preferences.eqTreble.key) private var eqTreble = Preferences.eqTreble.defaultValue
    @AppStorage(Preferences.typingProfile.key) private var typingProfile = Preferences.typingProfile.defaultValue
    @AppStorage(Preferences.typingVolume.key) private var typingVolume = Preferences.typingVolume.defaultValue
    @AppStorage(Preferences.ambientKind.key) private var ambientKind = Preferences.ambientKind.defaultValue
    @AppStorage(Preferences.ambientVolume.key) private var ambientVolume = Preferences.ambientVolume.defaultValue

    /// Applies the equalizer settings; the service exists only from macOS 14.2.
    private func refreshEqualizer() {
        if #available(macOS 14.2, *) { EqualizerService.shared.apply() }
    }

    /// One equalizer band: a slider from -12 to +12 dB that reapplies the equalizer as it moves.
    private func equalizerRow(_ title: LocalizedStringKey, _ gain: Binding<Double>) -> some View {
        SettingsRow(title: title) { Slider(value: gain, in: -12...12).frame(width: 180).onChange(of: gain.wrappedValue) { _, _ in refreshEqualizer() } }
    }

    var body: some View {
        SettingsPage(pane: .audio) {
            SettingsCard(title: "Music") {
                SettingsToggle("Show music playing in a browser", "Chrome, Edge, Brave, Arc, Chromium and Safari, once the browser allows JavaScript from Apple Events. Firefox is not supported.", isOn: $browserMusic, needs: .browsers)
            }
            SettingsCard {
                SettingsToggle("Live audio spectrum", "The equalizer follows the real sound. Asks for audio capture.", isOn: $liveSpectrum)
            }
            if #available(macOS 14.2, *) {
                SettingsCard(title: "Equalizer") {
                    SettingsToggle("System equalizer", "Shapes everything the Mac plays. Needs System Audio Recording. Off by default.", isOn: $systemEQ)
                        .onChange(of: systemEQ) { _, _ in refreshEqualizer() }
                    if systemEQ {
                        equalizerRow("Bass", $eqBass)
                        equalizerRow("Mid", $eqMid)
                        equalizerRow("Treble", $eqTreble)
                    }
                }
            }
            SettingsCard(title: "Sounds") {
                SettingsRow(title: "Typing sounds", subtitle: "A click on every key press, made on the Mac. Needs Input Monitoring. Which keys you press is never kept.") {
                    HStack(spacing: 8) {
                        Picker("", selection: $typingProfile) { ForEach(TypingSounds.Profile.allCases) { Text(verbatim: $0.title).tag($0.rawValue) } }.labelsHidden().frame(width: 110)
                        Button("Try") { TypingSounds.shared.preview(TypingSounds.Profile(rawValue: typingProfile) ?? .soft) }.controlSize(.small).disabled(typingProfile == "off")
                    }
                }
                if typingProfile != "off" { SettingsRow(title: "Typing volume") { Slider(value: $typingVolume, in: 0.05...1).frame(width: 180) } }
                SettingsRow(title: "Ambient sound during focus", subtitle: "Plays while a Focus session runs and fades out when it ends. Also in the Timer tab and the palette.") {
                    Picker("", selection: $ambientKind) { ForEach(AmbientNoise.Kind.allCases) { Text(verbatim: $0.title).tag($0.rawValue) } }.labelsHidden().frame(width: 150)
                }
                if ambientKind != "off" {
                    SettingsRow(title: "Ambient volume") { Slider(value: $ambientVolume, in: 0.05...1).frame(width: 180).onChange(of: ambientVolume) { _, new in AmbientNoise.shared.setVolume(Float(new)) } }
                }
            }
        }
    }
}
