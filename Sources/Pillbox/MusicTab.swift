import AppKit
import Foundation
import SwiftUI

struct MusicTab: View {
    @ObservedObject var music = MusicService.shared
    @ObservedObject var mixer = AppVolumeService.shared

    var body: some View {
        if mixer.showing {
            AppVolumeView()
        } else if !music.hasTrack {
            EmptyState(symbol: "music.note.list", title: "Nothing playing", message: "Start Spotify or Apple Music",
                       actionTitle: AppVolumeService.supported ? "App volume" : nil, action: AppVolumeService.supported ? { mixer.showing = true } : nil)
        } else {
            HStack(spacing: 14) {
                Group {
                    if let a = music.artwork { Image(nsImage: a).resizable() }
                    else { Rectangle().fill(card).overlay(Image(systemName: "music.note")) }
                }
                .frame(width: 190, height: 190).clipShape(RoundedRectangle(cornerRadius: Design.artworkRadius, style: .continuous))
                .shadow(color: .black.opacity(0.6), radius: 10, y: 4)
                .onTapGesture { music.openPlayer() }

                VStack(alignment: .leading, spacing: 4) {
                    Text(music.title).font(.system(size: 20, weight: .bold)).lineLimit(1)
                    Text(music.artist).font(Design.body).foregroundStyle(.secondary).lineLimit(1)
                    if let lyric = music.currentLine {
                        LiveLyricLine(line: lyric).font(Design.bodyMedium).lineLimit(2)
                            .id(lyric.id).transition(.opacity).animation(.easeInOut(duration: 0.25), value: lyric.id)
                    }
                    Spacer(minLength: 0)
                    ProgressBar(value: music.position, total: music.duration) { music.seek(to: $0) }
                    HStack(spacing: 6) {
                        Image(systemName: music.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { Double(music.volume) }, set: { music.setVolume(Int($0.rounded())) }), in: 0...100)
                            .controlSize(.mini).accessibilityLabel(Text("Volume"))
                    }
                    HStack {
                        Text(TimerService.format(music.position)); Spacer(); Text(TimerService.format(music.duration))
                    }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    HStack(spacing: 26) {
                        Spacer()
                        Button { music.previous() } label: { Image(systemName: "backward.fill") }.accessibilityLabel("Previous track")
                        Button { music.playPause() } label: {
                            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                                .frame(width: 38, height: 38).background(.white, in: Circle())
                        }.accessibilityLabel(LocalizedStringKey(music.isPlaying ? "Pause" : "Play"))
                        Button { music.next() } label: { Image(systemName: "forward.fill") }.accessibilityLabel("Next track")
                        Spacer()
                        Button { music.toggleShuffle() } label: { Image(systemName: "shuffle").foregroundStyle(music.shuffling ? Color.accentColor : .white.opacity(0.6)) }.accessibilityLabel("Shuffle").accessibilityAddTraits(music.shuffling ? .isSelected : [])
                        Button { music.toggleRepeat() } label: { Image(systemName: "repeat").foregroundStyle(music.repeating ? Color.accentColor : .white.opacity(0.6)) }.accessibilityLabel("Repeat").accessibilityAddTraits(music.repeating ? .isSelected : [])
                        if music.player == .music { Button { music.favorite() } label: { Image(systemName: music.favorited ? "heart.fill" : "heart").foregroundStyle(music.favorited ? Color.pink : .white.opacity(0.6)) }.accessibilityLabel("Favorite").accessibilityAddTraits(music.favorited ? .isSelected : []) }
                        if AppVolumeService.supported { Button { mixer.showing = true } label: { Image(systemName: "slider.horizontal.3").foregroundStyle(.white.opacity(0.6)) }.accessibilityLabel("App volume").hoverTip(localized("App volume")) }
                    }.buttonStyle(.plain).font(.system(size: 16))
                }
            }
        }
    }
}

/// Per-app volume: every app playing sound, with a mute button and a volume bar.
struct AppVolumeView: View {
    @ObservedObject var mixer = AppVolumeService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("App volume", systemImage: "slider.horizontal.3").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { mixer.showing = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5)) }
                    .buttonStyle(.plain).accessibilityLabel("Close").hoverTip(localized("Close"))
            }
            if mixer.apps.isEmpty {
                Text("No app is playing sound").font(Design.label).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let rows = VStack(spacing: 4) { ForEach(mixer.apps) { AppVolumeRow(app: $0) } }
                if mixer.apps.count > 4 { ScrollView { rows }.scrollIndicators(.never) } else { rows; Spacer(minLength: 0) }
            }
        }
        .onAppear { mixer.watch(true) }
        .onDisappear { mixer.watch(false) }
    }
}

struct AppVolumeRow: View {
    let app: AppAudio
    @ObservedObject var mixer = AppVolumeService.shared
    @State private var editing = false

    var body: some View {
        let muted = mixer.isMuted(app.id), g = mixer.gain(app.id)
        let shaped = mixer.equalizer(app.id).contains { $0 != 0 }
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Group {
                    if let i = app.icon { Image(nsImage: i).resizable() } else { Image(systemName: "app.fill").resizable() }
                }.frame(width: 18, height: 18)
                Text(verbatim: app.name).font(.system(size: 11, weight: .medium)).lineLimit(1).frame(width: 120, alignment: .leading)
                Button { mixer.toggleMute(app.id) } label: {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").foregroundStyle(muted ? Color.red : .white.opacity(0.7))
                        .frame(width: 18)
                }.buttonStyle(.plain).accessibilityLabel(LocalizedStringKey(muted ? "Unmute" : "Mute")).hoverTip(localized(muted ? "Unmute" : "Mute"))
                VolumeBar(value: Double(muted ? 0 : g) / Double(AppVolumeMath.maxGain)) { mixer.setGain(Float($0) * AppVolumeMath.maxGain, for: app.id) }
                    .opacity(muted ? 0.4 : 1).accessibilityLabel(Text(verbatim: app.name))
                Text(verbatim: "\(Int((muted ? 0 : g) * 100)) %").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                Button { editing.toggle() } label: {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(shaped || editing ? Color.accentColor : .white.opacity(0.7))
                }.buttonStyle(.plain).accessibilityLabel(LocalizedStringKey("Equalizer")).hoverTip(localized("Equalizer"))
            }
            .frame(height: 26)
            if editing {
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(["Bass", "Mid", "Treble"][i])).font(.system(size: 10, weight: .medium)).frame(width: 120, alignment: .leading)
                        Slider(value: band(i), in: -12...12).controlSize(.small)
                        Text(verbatim: String(format: "%+.0f dB", mixer.equalizer(app.id)[i])).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, editing ? 6 : 0)
        .background(card, in: RoundedRectangle(cornerRadius: Design.rowRadius))
    }

    /// One band of this app's equalizer; each move is stored and applied to its tap.
    private func band(_ i: Int) -> Binding<Double> {
        Binding(get: { mixer.equalizer(app.id)[i] }, set: { v in
            var bands = mixer.equalizer(app.id)
            bands[i] = v
            mixer.setEqualizer(bands, for: app.id)
        })
    }
}

/// A drag bar that reports while dragging (ProgressBar seeks on release).
struct VolumeBar: View {
    let value: Double
    let onChange: (Double) -> Void
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(.white).frame(width: g.size.width * min(max(value, 0), 1))
            }
            .frame(height: 5).frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { onChange(min(max($0.location.x / g.size.width, 0), 1)) })
        }.frame(height: 18)
        .accessibilityValue(Text(verbatim: "\(Int(value * 100)) %"))
        .accessibilityAdjustableAction { dir in onChange(min(max(value + (dir == .increment ? 0.1 : -0.1), 0), 1)) }
    }
}

/// A bar that seeks on release. Without `onSeek` it only shows the value.
struct ProgressBar: View {
    let value: Double, total: Double
    var onSeek: ((Double) -> Void)? = nil
    var body: some View {
        GeometryReader { g in
            let bar = ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(.white).frame(width: g.size.width * (total > 0 ? min(value / total, 1) : 0))
            }
            .contentShape(Rectangle())
            if let onSeek {
                bar.gesture(DragGesture(minimumDistance: 0).onEnded { onSeek(total * min(max($0.location.x / g.size.width, 0), 1)) })
            } else {
                bar
            }
        }.frame(height: 5)
    }
}
