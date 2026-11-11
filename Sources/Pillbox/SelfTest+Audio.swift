import AppKit
import SwiftUI
import SQLite3
import AVFoundation
import PDFKit
import ImageIO

extension SelfTest {
    static func lyrics() {
        let l = MusicService.parseLRC("[00:12.50] Hello\n[01:02.00]World\n[00:30.00]\nnot a line")
        check("LRC parses timestamps and skips empty lines", l.count == 2 && l[0].time == 12.5 && l[1].time == 62 && l[1].text == "World", "\(l.map(\.time))")
    }

    static func appVolume() {
        let apps = ["com.google.Chrome", "com.google.Chrome.canary", "com.apple.Safari", "com.spotify.client"]
        check("app volume: helpers belong to their app", AppVolumeMath.owner(of: "com.google.Chrome.helper", among: apps) == "com.google.Chrome"
              && AppVolumeMath.owner(of: "com.google.Chrome.canary.helper", among: apps) == "com.google.Chrome.canary"
              && AppVolumeMath.owner(of: "com.spotify.client", among: apps) == "com.spotify.client")
        check("app volume: WebKit audio goes to Safari, strangers to nobody", AppVolumeMath.owner(of: "com.apple.WebKit.GPU", among: apps) == "com.apple.Safari"
              && AppVolumeMath.owner(of: "com.apple.WebKit.GPU", among: ["com.spotify.client"]) == nil && AppVolumeMath.owner(of: "com.google.Chromebook", among: apps) == nil)
        check("app volume: a tap only below 100 % or muted", !AppVolumeMath.needsTap(gain: 1, muted: false) && AppVolumeMath.needsTap(gain: 0.5, muted: false) && AppVolumeMath.needsTap(gain: 1, muted: true))
        check("app volume: channel mapping", AppVolumeMath.source(for: 1, inputs: 2) == 1 && AppVolumeMath.source(for: 1, inputs: 1) == 0 && AppVolumeMath.source(for: 3, inputs: 2) == nil)
        let list = AudioBufferList.allocate(maximumBuffers: 3); defer { free(list.unsafeMutablePointer) }
        let a = UnsafeMutablePointer<Float>.allocate(capacity: 8), b = UnsafeMutablePointer<Float>.allocate(capacity: 4), c = UnsafeMutablePointer<Float>.allocate(capacity: 4)
        defer { a.deallocate(); b.deallocate(); c.deallocate() }
        list[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 32, mData: a)
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16, mData: b)
        list[2] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16, mData: c)
        let ch = AppVolumeMath.channel(list, from: 1, 1)
        check("app volume: planar and interleaved buffers read alike", AppVolumeMath.channelCount(list, from: 0) == 4 && AppVolumeMath.channelCount(list, from: 1) == 2
              && ch?.0 == c && ch?.1 == 0 && ch?.2 == 1 && ch?.3 == 4 && AppVolumeMath.channel(list, from: 0, 1).map { $0.0 == a && $0.1 == 1 && $0.2 == 2 && $0.3 == 4 } == true
              && AppVolumeMath.channel(list, from: 1, 2) == nil)
    }

    static func spectrum() {
        let rate = 48_000.0
        let tone = (0..<1024).map { Float(sin(2 * Double.pi * 1400 * Double($0) / rate)) }
        let levels = Goertzel.levels(tone, sampleRate: rate)
        check("spectrum: a 1.4 kHz tone lights the 1.4 kHz band the most", levels.firstIndex(of: levels.max()!) == 3, "\(levels)")
        check("spectrum: silence is flat", Goertzel.levels([Float](repeating: 0, count: 1024), sampleRate: rate).allSatisfy { $0 == 0 })
    }

    static func playerAndLyrics() {
        check("player: swipe left is next, right is previous", swipeAction(dx: -80, dy: 5) == .next && swipeAction(dx: 80, dy: -5) == .previous)
        check("player: short or vertical drags do nothing", swipeAction(dx: -30, dy: 0) == nil && swipeAction(dx: 60, dy: 80) == nil)
        check("player: four sizes, growing", PlayerSize.allCases.map(\.rawValue) == PlayerSize.allCases.map(\.rawValue).sorted() && PlayerSize.allCases.count == 4)
        let ls = [LyricLine(time: 1, text: "a"), LyricLine(time: 5, text: "b"), LyricLine(time: 9, text: "c")]
        check("lyrics: the current line follows the playback position", LyricsScreenView.currentIndex(ls, at: 0) == nil && LyricsScreenView.currentIndex(ls, at: 5.5) == 1 && LyricsScreenView.currentIndex(ls, at: 99) == 2)
    }

    static func equalizer() {
        check("equalizer: real levels set the bar, a wave otherwise, and both stay in range",
              Equalizer.barHeight(index: 0, time: 0, levels: [0, 1, 0, 0, 0, 0]) == 16 && Equalizer.barHeight(index: 0, time: 0, levels: [0, 0, 0, 0, 0, 0]) == 3
              && (5...16).contains(Equalizer.barHeight(index: 2, time: 1.7, levels: nil)))
    }

    static func equalizerAndLyricStamps() {
        let eqPeak = Biquad.gainDB(Biquad.peak(1_000, gainDB: 6, rate: 48_000), at: 1_000, rate: 48_000)
        let eqShelf = Biquad.gainDB(Biquad.shelf(100, gainDB: 12, rate: 48_000, high: false), at: 20, rate: 48_000)
        check("equalizer: a peak band gives its gain at its centre, a shelf its gain well below the corner",
              abs(eqPeak - 6) < 0.01 && abs(eqShelf - 12) < 0.5, "\(eqPeak) \(eqShelf)")
        let stamped = MusicService.parseLRC("[00:10.00]<00:10.00>Hello <00:10.50>world\n[00:14.00]Plain line here")
        let plain = stamped.last?.words ?? []
        check("lyrics: word stamps are read, and a plain line spreads its words up to the next line",
              stamped.first?.words.map(\.text) == ["Hello", "world"] && stamped.first?.words.last?.time == 10.5
              && plain.map(\.text) == ["Plain", "line", "here"] && plain[0].time == 14 && abs(plain[1].time - (14 + 4.0 / 3)) < 0.01,
              "\(stamped)")
    }

    static func appEqualizerAndBoost() {
        check("app equalizer: a shaped app needs a tap even at full volume, a flat one does not",
              AppVolumeMath.needsTap(gain: 1, muted: false, equalized: true) && !AppVolumeMath.needsTap(gain: 1, muted: false, equalized: false))
        check("app boost: above 100 % needs a tap and is capped at 150 %",
              AppVolumeMath.needsTap(gain: 1.3, muted: false) && AppVolumeMath.maxGain == 1.5)
    }

    static func typingSounds() {
        let key = KeySynth.sample(.thock, kind: .press), n = Int(key.frameLength), samples = (0..<n).map { key.floatChannelData![0][$0] }
        // Finite and audible. Its range is not checked: the synthesiser clamps every sample, so that could not fail.
        check("typing sounds: a synthesised key is finite and audible", n > 1000 && samples.allSatisfy { $0.isFinite } && (samples.map { abs($0) }.max() ?? 0) > 0.05)
    }

    static func ambientNoise() {
        let noise = NoiseState(); noise.kind = .pink
        let pink = (0..<20000).map { _ in noise.next() }; noise.kind = .brown; let brown = (0..<20000).map { _ in noise.next() }
        check("ambient noise: pink and brown stay finite and bounded", (pink + brown).allSatisfy { $0.isFinite && abs($0) < 1.5 } && (brown.map { abs($0) }.max() ?? 0) > 0.01)
    }
}
