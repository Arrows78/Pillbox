import SwiftUI

private let card = DS.card

struct HomeTab: View {
    @ObservedObject var battery = BatteryService.shared
    @ObservedObject var stats = StatsService.shared
    @ObservedObject var calendar = CalendarService.shared
    @ObservedObject var caffeine = CaffeineService.shared
    @ObservedObject var timer = TimerService.shared
    @ObservedObject var audio = AudioControl.shared
    @ObservedObject var weather = WeatherService.shared
    @ObservedObject var batteryLog = BatteryLog.shared
    @State private var batteryChart = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(ctx.date, format: .dateTime.hour().minute()).font(.system(size: 34, weight: .semibold, design: .rounded))
                }
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide)).font(.system(size: 12)).foregroundStyle(.secondary)
                if let t = weather.temperature {
                    Label("\(t)° \(weather.summary)\(weather.city.isEmpty ? "" : " · " + weather.city)", systemImage: weather.symbol)
                        .font(.system(size: 11)).symbolRenderingMode(.multicolor).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                NetworkLine(down: stats.down, up: stats.up, samples: stats.netHistory)
                ForEach(stats.bluetooth, id: \.self) { line in
                    Label { Text(verbatim: line) } icon: { Image(systemName: "airpodspro") }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                if !stats.devices.isEmpty {
                    Label(stats.devices.map { "\($0.name) \($0.percent)%" }.joined(separator: " · "), systemImage: "battery.75percent")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(width: 190, alignment: .leading)

            VStack(spacing: 8) {
                HomeNowPlaying()
                HomeUpNext()
            }.frame(maxWidth: .infinity)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    gauge("CPU", stats.cpu, .green)
                    gauge("RAM", stats.memory, .blue)
                    gauge("Batt", Double(battery.level) / 100, battery.level < 20 ? .red : .yellow, icon: battery.pluggedIn ? "bolt.fill" : nil, detail: batteryLog.remaining)
                        .contentShape(Rectangle()).onTapGesture { batteryChart = true }.hoverTip(L("Battery history"))
                        .accessibilityAddTraits(.isButton).accessibilityAction { batteryChart = true }
                }
                .opacity(batteryChart ? 0 : 1)
                .overlay {   // same footprint as the gauges, so the column never grows
                    if batteryChart {
                        BatteryChartCard(samples: batteryLog.history, level: battery.level, remaining: batteryLog.remaining,
                                         health: batteryLog.health, hasBattery: batteryLog.hasBattery)
                            .contentShape(Rectangle()).onTapGesture { batteryChart = false }
                            .accessibilityAddTraits(.isButton).accessibilityAction { batteryChart = false }
                    }
                }
                VStack(spacing: 8) {
                HStack(spacing: 8) {
                    quick("cup.and.saucer.fill", "Awake", active: caffeine.active) { caffeine.toggle() }
                        .contextMenu {
                            Button("30 minutes") { caffeine.start(minutes: 30) }
                            Button("1 hour") { caffeine.start(minutes: 60) }
                            Button("2 hours") { caffeine.start(minutes: 120) }
                            Button("Until 6 pm") { caffeine.start(until: 18) }
                            Button("Until turned off") { caffeine.start() }
                            if caffeine.active { Divider(); Button("Turn off") { caffeine.stop() } }
                        }
                    quick("eyedropper", "Color") { Tools.pickColor() }
                    quick("camera.viewfinder", "Capture") { Tools.captureArea() }
                }
                HStack(spacing: 8) {
                    quick("mic.slash.fill", "Mute", active: audio.micMuted) { audio.toggleMic() }
                    quick("video.fill", "Mirror") { CameraMirror.shared.toggle() }
                    quick("timer", "Focus", active: timer.running) { timer.mode = .focus; timer.toggle() }
                }
                }
            }.frame(width: 280)
        }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    private func gauge(_ name: LocalizedStringKey, _ v: Double, _ c: Color, icon: String? = nil, detail: String? = nil) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(c.opacity(0.2), lineWidth: 5)
                Circle().trim(from: 0, to: v).stroke(c, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                if let icon { Image(systemName: icon).font(.system(size: 10)).foregroundStyle(c) }
                else { Text("\(Int(v * 100))").font(.system(size: 11, weight: .semibold, design: .rounded)) }
            }.frame(width: 46, height: 46)
            (Text(name) + Text(verbatim: detail.map { " · " + $0 } ?? "")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .accessibilityElement(children: .ignore).accessibilityLabel(Text(name)).accessibilityValue("\(Int(v * 100))%")
    }

    private func quick(_ symbol: String, _ title: LocalizedStringKey, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 17)).frame(height: 20)
                Text(title).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.75).padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(active ? Color.orange.opacity(0.30) : card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(active ? Color.orange.opacity(0.6) : DS.hairline, lineWidth: 0.5))
        }.buttonStyle(.plain)
    }
}

/// Home card: the current track with its controls, or a way to start the music.
struct HomeNowPlaying: View {
    @ObservedObject var music = MusicService.shared

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let a = music.artwork { Image(nsImage: a).resizable() }
                else { Rectangle().fill(.white.opacity(0.08)).overlay(Image(systemName: "music.note").foregroundStyle(.secondary)) }
            }
            .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: music.hasTrack ? music.title : L("Nothing playing")).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(music.hasTrack ? 1 : 0.8)
                Text(verbatim: music.hasTrack ? music.artist : L("Start Spotify or Apple Music")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(music.hasTrack ? 1 : 2)
                if music.hasTrack {
                    ProgressBar(value: music.position, total: music.duration) { music.seek(to: $0) }.frame(height: 4).padding(.top, 4)
                }
            }
            Spacer(minLength: 4)
            if music.hasTrack {
                HStack(spacing: 14) {
                    Button { music.previous() } label: { Image(systemName: "backward.fill") }.accessibilityLabel("Previous track")
                    Button { music.playPause() } label: { Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 15)) }
                        .accessibilityLabel(LocalizedStringKey(music.isPlaying ? "Pause" : "Play"))
                    Button { music.next() } label: { Image(systemName: "forward.fill") }.accessibilityLabel("Next track")
                }.buttonStyle(.plain).font(.system(size: 12))
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { NotchModel.shared.tab = .music }
    }
}

/// Home card: the next three timed events today and tomorrow, with Join for video calls.
struct HomeUpNext: View {
    @ObservedObject var agenda = AgendaModel.shared
    @ObservedObject var calendar = CalendarService.shared

    var body: some View {
        let upcoming = Array(agenda.events.filter { !$0.allDay && $0.end > Date() }.prefix(3))
        VStack(alignment: .leading, spacing: 8) {
            Text("Up next").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            if upcoming.isEmpty {
                Text(agenda.denied ? "Calendar access is off" : "No upcoming events").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            ForEach(upcoming) { e in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 3, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: e.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Group {
                            if e.start > Date() { Text(e.start, style: .relative) } else { Text("Now") }
                        }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let url = e.join {
                        Button { NSWorkspace.shared.open(url) } label: { Label("Join", systemImage: "video.fill") }.buttonStyle(PillButtonStyle(tint: .green))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { NotchModel.shared.tab = .calendar }
        .onAppear { agenda.refresh() }
        .onChange(of: calendar.next?.start) { _, _ in agenda.refresh() }
    }
}

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
                .frame(width: 190, height: 190).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.6), radius: 10, y: 4)
                .onTapGesture { music.openPlayer() }

                VStack(alignment: .leading, spacing: 4) {
                    Text(music.title).font(.system(size: 20, weight: .bold)).lineLimit(1)
                    Text(music.artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    if let l = music.currentLine {
                        LiveLyricLine(line: l).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            .id(l.id).transition(.opacity).animation(.easeInOut(duration: 0.25), value: l.id)
                    }
                    Spacer(minLength: 0)
                    ProgressBar(value: music.position, total: music.duration) { music.seek(to: $0) }
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
                        if music.player == .music { Button { music.favorite() } label: { Image(systemName: "heart").foregroundStyle(.white.opacity(0.6)) }.accessibilityLabel("Favorite") }
                        if AppVolumeService.supported { Button { mixer.showing = true } label: { Image(systemName: "slider.horizontal.3").foregroundStyle(.white.opacity(0.6)) }.accessibilityLabel("App volume").hoverTip(L("App volume")) }
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
                    .buttonStyle(.plain).accessibilityLabel("Close").hoverTip(L("Close"))
            }
            if mixer.apps.isEmpty {
                Text("No app is playing sound").font(.system(size: 11)).foregroundStyle(.secondary)
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

    var body: some View {
        let muted = mixer.isMuted(app.id), g = mixer.gain(app.id)
        HStack(spacing: 8) {
            Group {
                if let i = app.icon { Image(nsImage: i).resizable() } else { Image(systemName: "app.fill").resizable() }
            }.frame(width: 18, height: 18)
            Text(verbatim: app.name).font(.system(size: 11, weight: .medium)).lineLimit(1).frame(width: 120, alignment: .leading)
            Button { mixer.toggleMute(app.id) } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").foregroundStyle(muted ? Color.red : .white.opacity(0.7))
                    .frame(width: 18)
            }.buttonStyle(.plain).accessibilityLabel(LocalizedStringKey(muted ? "Unmute" : "Mute")).hoverTip(L(muted ? "Unmute" : "Mute"))
            VolumeBar(value: Double(muted ? 0 : g)) { mixer.setGain(Float($0), for: app.id) }
                .opacity(muted ? 0.4 : 1).accessibilityLabel(Text(verbatim: app.name))
            Text(verbatim: "\(Int((muted ? 0 : g) * 100)) %").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 8).frame(height: 26).background(card, in: RoundedRectangle(cornerRadius: 7))
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

struct ProgressBar: View {
    let value: Double, total: Double
    let onSeek: (Double) -> Void
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(.white).frame(width: g.size.width * (total > 0 ? min(value / total, 1) : 0))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { onSeek(total * min(max($0.location.x / g.size.width, 0), 1)) })
        }.frame(height: 5)
    }
}

struct TimerTab: View {
    @ObservedObject var t = TimerService.shared

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 7)
                Circle().trim(from: 0, to: t.progress).stroke(Color.orange, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90)).shadow(color: .orange.opacity(t.running ? 0.55 : 0), radius: 5)
                VStack(spacing: 0) {
                    if let e = Mascot.emoji(for: Mascot.current, progress: t.progress) { Text(e).font(.system(size: 20)).scaleEffect(t.running ? 1.08 : 1).animation(t.running ? .easeInOut(duration: 0.8).repeatForever() : .default, value: t.running) }
                    Text(t.display).font(.system(size: 30, weight: .semibold, design: .monospaced))
                    Text(LocalizedStringKey(t.mode.rawValue)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.frame(width: 180, height: 180)

            VStack(alignment: .leading, spacing: 8) {
                PillSegmented(options: TimerService.Mode.allCases, selection: $t.mode, tint: .orange) { LocalizedStringKey($0.rawValue) }
                HStack(spacing: 8) {
                    Button { t.toggle() } label: { Label(LocalizedStringKey(t.running ? "Pause" : "Start"), systemImage: t.running ? "pause.fill" : "play.fill") }
                        .buttonStyle(PillButtonStyle(tint: .orange))
                    Button("Reset") { t.reset() }.buttonStyle(PillButtonStyle())
                    if t.mode == .countdown { Button("Repeat") { t.repeatTimer() }.buttonStyle(PillButtonStyle()) }
                    AmbientMenu()
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Button { stepBinding.wrappedValue = max(1, stepBinding.wrappedValue - 1) } label: { Image(systemName: "minus") }.accessibilityLabel("Fewer minutes")
                        Text("\(stepBinding.wrappedValue) min").font(.system(size: 11, weight: .medium)).monospacedDigit().frame(minWidth: 44)
                        Button { stepBinding.wrappedValue = min(180, stepBinding.wrappedValue + 1) } label: { Image(systemName: "plus") }.accessibilityLabel("More minutes")
                    }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 10).padding(.vertical, 5).background(DS.card, in: Capsule())
                    .disabled(t.mode == .stopwatch || t.running).opacity(t.mode == .stopwatch || t.running ? 0.4 : 1)
                }
                HStack(spacing: 6) {
                    ForEach(t.mode.presets, id: \.self) { m in
                        let on = stepBinding.wrappedValue == m
                        Button { stepBinding.wrappedValue = m } label: {
                            Text("\(m) min").font(.system(size: 11, weight: .medium)).monospacedDigit()
                                .foregroundStyle(on ? .white : .white.opacity(0.7))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(on ? Color.orange.opacity(0.35) : DS.card, in: Capsule())
                                .overlay(Capsule().strokeBorder(on ? Color.orange.opacity(0.7) : DS.hairline, lineWidth: 0.5))
                        }.buttonStyle(.plain).disabled(t.running)
                    }
                    if t.mode == .stopwatch { Text("Counts up until you stop it").font(.system(size: 11)).foregroundStyle(DS.secondary) }
                    Spacer(minLength: 0)
                }.opacity(t.running ? 0.6 : 1)
                TextField("Name this timer", text: $t.label).pillField()
                HStack(spacing: 10) {
                    Toggle("Chain", isOn: $t.chain).toggleStyle(.switch).controlSize(.mini).tint(.orange).font(.system(size: 11))
                    Label("\(t.streak) day streak", systemImage: "flame.fill").font(.system(size: 11)).foregroundStyle(.orange)
                    Spacer()
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(t.week.enumerated()), id: \.offset) { _, d in
                            Capsule().fill(d.count > 0 ? Color.orange : .white.opacity(0.15))
                                .frame(width: 5, height: 4 + CGFloat(min(d.count, 6)) * 3)
                        }
                    }.frame(height: 24, alignment: .bottom).hoverTip(L("Focus sessions, last 7 days"))
                }
            }
        }
    }

    private var stepBinding: Binding<Int> {
        switch t.mode {
        case .focus: $t.focusMinutes
        case .rest: $t.breakMinutes
        default: $t.countdownMinutes
        }
    }
}

struct NotesTab: View {
    @ObservedObject var store = NotesStore.shared
    @ObservedObject var model = NotchModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: DS.gap) {
            HStack(spacing: DS.gap) {
                TextField("Jot something down…", text: $store.draft).pillField().focused($focused)
                    .onSubmit { store.add() }
                if store.notes.contains(where: \.done) { Button("Clear done") { store.clearDone() }.buttonStyle(PillButtonStyle()).fixedSize() }
            }
            .onChange(of: focused) { model.pinnedOpen = $0 }
            if store.notes.isEmpty {
                EmptyState(symbol: "note.text", title: "No notes yet", message: "Quick notes and to-dos stay here until you check them off")
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.notes) { n in
                            HStack(spacing: 8) {
                                Button { store.toggle(n) } label: { Image(systemName: n.done ? "checkmark.circle.fill" : "circle").foregroundStyle(n.done ? Color.yellow : DS.secondary) }.buttonStyle(.plain).accessibilityLabel(LocalizedStringKey(n.done ? "Mark as not done" : "Mark as done"))
                                Text(n.text).strikethrough(n.done).foregroundStyle(n.done ? DS.secondary : .white).lineLimit(2)
                                Spacer(minLength: 0)
                                IconButton(symbol: "trash", label: L("Delete")) { store.remove(n) }
                            }
                            .font(.system(size: 12)).padding(.leading, 10).padding(.trailing, 4).padding(.vertical, 3).rowCard()
                            .contextMenu {
                                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(n.text, forType: .string) }
                                Button(LocalizedStringKey(n.done ? "Mark as not done" : "Mark as done")) { store.toggle(n) }
                                Button("Delete", role: .destructive) { store.remove(n) }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ClipboardHistory: View {
    @Binding var mode: Int
    @ObservedObject var clip = ClipboardService.shared
    @ObservedObject var model = NotchModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: DS.gap) {
            HStack(spacing: DS.gap) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(DS.secondary)
                    TextField("Search text and screenshots", text: $clip.query).textFieldStyle(.plain).font(.system(size: 12)).focused($focused)
                    if !clip.query.isEmpty {
                        Button { clip.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DS.secondary) }.buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10).frame(height: 28)
                .background(DS.card, in: Capsule()).overlay(Capsule().strokeBorder(DS.hairline, lineWidth: 0.5))
                HStack(spacing: 2) {
                    ForEach(ClipFilter.allCases) { f in
                        FilterChip(symbol: f.symbol, label: L(f.label), selected: clip.filter == f, tint: .mint) { clip.filter = f }
                    }
                }
                IconButton(symbol: "trash", label: L("Clear history (pinned items stay)")) { clip.clearUnpinned() }
                ClipboardModePicker(mode: $mode)
            }
            .onChange(of: focused) { model.pinnedOpen = $0 }
            let items = clip.filtered
            if items.isEmpty {
                if clip.items.isEmpty { EmptyState(symbol: "doc.on.clipboard", title: "Clipboard history is empty", message: "Copy text or an image and it shows up here") }
                else { EmptyState(symbol: "magnifyingglass", title: "No matches", actionTitle: "Show all") { clip.query = ""; clip.filter = .all } }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: DS.gap) {
                        ForEach(items) { item in ClipCard(item: item) }
                    }.padding(.trailing, 24)
                }.trailingFade()
            }
        }
    }
}

struct ClipboardTab: View {
    @State private var mode = 0
    var body: some View {
        if mode == 0 { ClipboardHistory(mode: $mode) } else { SnippetsView(mode: $mode) }
    }
}

struct ClipboardModePicker: View {
    @Binding var mode: Int
    var body: some View {
        PillSegmented(options: [0, 1], selection: $mode, tint: .mint.opacity(0.45)) { $0 == 0 ? "History" : "Snippets" }.frame(width: 190)
    }
}

struct SnippetsView: View {
    @Binding var mode: Int
    @ObservedObject var store = SnippetsStore.shared
    @ObservedObject var model = NotchModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: DS.gap) {
                ClipboardModePicker(mode: $mode)
                TextField("Name", text: $store.draftName).pillField().focused($focused)
                TextField("Text to paste", text: $store.draftText, axis: .vertical).lineLimit(2, reservesSpace: true).pillField().focused($focused)
                Button("Save snippet") { store.add() }.buttonStyle(PillButtonStyle(tint: .mint.opacity(0.45)))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: 220)
            .onChange(of: focused) { model.pinnedOpen = $0 }
            if store.snippets.isEmpty {
                EmptyState(symbol: "text.quote", title: "No snippets yet", message: "Save text you paste often, then paste it from the palette")
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.snippets) { sn in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(sn.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(sn.text).font(.system(size: 10)).foregroundStyle(DS.secondary).lineLimit(1)
                                }
                                Spacer()
                                IconButton(symbol: "trash", label: L("Delete")) { store.remove(sn) }
                            }
                            .padding(.leading, 10).padding(.trailing, 4).padding(.vertical, 4).rowCard()
                            .onTapGesture { store.paste(sn) }
                            .contextMenu {
                                Button("Paste") { store.paste(sn) }
                                Button("Delete") { store.remove(sn) }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ClipCard: View {
    let item: ClipItem
    @ObservedObject var clip = ClipboardService.shared
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content.frame(width: 156, alignment: .topLeading).frame(maxHeight: .infinity, alignment: .topLeading).clipped()
            HStack(spacing: 5) {
                Image(systemName: kindSymbol).foregroundStyle(DS.secondary)
                if item.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                Text(item.date, style: .relative).foregroundStyle(DS.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if hovering {
                    if let u = link { cardButton("safari", L("Open link")) { NSWorkspace.shared.open(u) } }
                    cardButton(item.pinned ? "pin.slash" : "pin", L(item.pinned ? "Unpin" : "Pin")) { clip.togglePin(item) }
                    cardButton("trash", L("Delete")) { clip.remove(item) }
                }
            }.font(.system(size: 9)).frame(height: 14)
        }
        .padding(10).rowCard(radius: 10)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { clip.paste(item) }
        .onTapGesture { clip.copy(item); NotchModel.shared.show(Activity(symbol: "doc.on.doc.fill", title: "Copied", duration: 1.2)) }
        .contextMenu {
            Button("Copy") { clip.copy(item) }
            Button("Paste") { clip.paste(item) }
            if let u = link { Button("Open link") { NSWorkspace.shared.open(u) } }
            if let t = item.text, case .email(let e) = ClipboardService.kind(of: t), let u = URL(string: "mailto:\(e)") {
                Button("Send email") { NSWorkspace.shared.open(u) }
            }
            Divider()
            Button(LocalizedStringKey(item.pinned ? "Unpin" : "Pin")) { clip.togglePin(item) }
            Button("Delete", role: .destructive) { clip.remove(item) }
        }
    }

    private var link: URL? {
        if let t = item.text, case .url(let u) = ClipboardService.kind(of: t) { return u }
        return nil
    }

    private var kindSymbol: String {
        guard let t = item.text else { return ClipFilter.images.symbol }
        switch ClipboardService.kind(of: t) {
        case .url: return ClipFilter.links.symbol
        case .color: return ClipFilter.colors.symbol
        case .email: return "envelope"
        case .plain: return ClipFilter.text.symbol
        }
    }

    private func cardButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 14, height: 14) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel(Text(verbatim: label))
    }

    @ViewBuilder private var content: some View {
        if let img = clip.image(for: item) {
            Image(nsImage: img).resizable().scaledToFill().frame(width: 156).frame(maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let t = item.text {
            switch ClipboardService.kind(of: t) {
            case .color(let c, let hex):
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: c)).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.hairline, lineWidth: 0.5))
                        .frame(maxHeight: 96)
                    Text(hex.uppercased()).font(.system(size: 11, weight: .medium, design: .monospaced))
                    let rgb = c.usingColorSpace(.sRGB) ?? c
                    Text(verbatim: "rgb(\(Int(rgb.redComponent * 255)), \(Int(rgb.greenComponent * 255)), \(Int(rgb.blueComponent * 255)))")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(DS.secondary)
                }
            default:
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.trimmingCharacters(in: .whitespacesAndNewlines)).font(.system(size: 11)).lineLimit(9)
                    if t.count > 140 { Text("\(t.count) chars · \(t.split(whereSeparator: \.isWhitespace).count) words").font(.system(size: 9)).foregroundStyle(DS.secondary) }
                }
            }
        }
    }
}

struct ShelfTab: View {
    @ObservedObject var shelf = ShelfService.shared

    var body: some View {
        if shelf.items.isEmpty {
            EmptyState(symbol: "tray.and.arrow.down", title: "Drop files on the notch to stash them", message: "They stay here, ready to drag out or send",
                       actionTitle: "Add files…", tint: .cyan) { shelf.browse() }
        } else {
            VStack(spacing: DS.gap) {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: DS.gap)], spacing: DS.gap) {
                        ForEach(shelf.items) { ShelfCell(item: $0) }
                        Button { shelf.browse() } label: {
                            Image(systemName: "plus").font(.system(size: 16, weight: .medium)).foregroundStyle(DS.secondary)
                                .frame(maxWidth: .infinity).frame(height: ShelfCell.height)
                        }.buttonStyle(.plain).rowCard(radius: 10).hoverTip(L("Add files…")).accessibilityLabel("Add files…")
                    }
                }
                HStack(spacing: 6) {
                    let target = shelf.selection.isEmpty ? shelf.items : shelf.selected
                    Button { shelf.airDrop(target) } label: { Label("AirDrop", systemImage: "dot.radiowaves.left.and.right") }.buttonStyle(PillButtonStyle(tint: .cyan.opacity(0.55)))
                    Button("Zip / Unzip") { shelf.zipOrUnzip(target) }.buttonStyle(PillButtonStyle())
                    let kinds = Array(Set(target.flatMap { ConvertTarget.targets(for: $0.url) })).sorted { $0.rawValue < $1.rawValue }
                    if !kinds.isEmpty {
                        Menu {
                            ForEach(kinds) { k in Button(LocalizedStringKey(k.rawValue)) { shelf.convert(target.filter { ConvertTarget.targets(for: $0.url).contains(k) }, to: k) } }
                        } label: { Text("Convert").font(.system(size: 11, weight: .semibold)) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .padding(.horizontal, 12).padding(.vertical, 5).background(Color.white.opacity(0.12), in: Capsule())
                    }
                    Button("Reveal") { shelf.reveal(target) }.buttonStyle(PillButtonStyle())
                    if target.count == 1, let one = target.first, Annotator.canAnnotate(one.url) { Button("Annotate") { Annotator.open(one.url) }.buttonStyle(PillButtonStyle()) }
                    Spacer(minLength: 6)
                    Text(verbatim: ShelfService.summary(count: shelf.items.count, selected: shelf.selection.count))
                        .font(.system(size: 11)).foregroundStyle(DS.secondary).lineLimit(1).fixedSize()
                    IconButton(symbol: "trash", label: L("Clear the shelf")) { shelf.clear() }
                }
            }
        }
    }
}

struct ShelfCell: View {
    static let height: CGFloat = 100
    let item: ShelfItem
    @ObservedObject var shelf = ShelfService.shared

    var body: some View {
        let selected = shelf.selection.contains(item.id)
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path)).resizable().frame(width: 48, height: 48)
            Text(verbatim: item.name).font(.system(size: 10)).lineLimit(2).truncationMode(.middle).multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
        }
        .padding(.horizontal, 6).frame(maxWidth: .infinity).frame(height: Self.height)
        .rowCard(radius: 10, selected: selected ? Color.cyan.opacity(0.3) : nil)
        .overlay(alignment: .topTrailing) {
            if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.cyan).padding(5) }
        }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .onTapGesture { if selected { shelf.selection.remove(item.id) } else { shelf.selection.insert(item.id) } }
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .contextMenu {
            Button("Open with default app") { NSWorkspace.shared.open(item.url) }
            Button("Reveal in Finder") { shelf.reveal([item]) }
            if Annotator.canAnnotate(item.url) { Button("Annotate") { Annotator.open(item.url) } }
            Button("AirDrop") { shelf.airDrop([item]) }
            Button("Copy path") { shelf.copyPaths([item]) }
            Divider()
            Button("Remove from shelf", role: .destructive) { shelf.remove([item.id]) }
        }
    }
}

struct LauncherTab: View {
    @State private var mode = 0
    var body: some View {
        VStack(spacing: DS.gap) {
            PillSegmented(options: [0, 1, 2], selection: $mode, tint: .indigo) { ["Apps", "Shortcuts", "Actions"][$0] }.frame(width: 300)
            if mode == 0 { AppsGrid() } else if mode == 1 { ShortcutsGrid() } else { ActionsGrid() }
        }
    }
}

struct ShortcutsGrid: View {
    @ObservedObject var svc = ShortcutsService.shared
    var body: some View {
        ScrollView {
            if svc.names.isEmpty { EmptyState(symbol: "bolt", title: "No shortcuts found. Create some in the Shortcuts app.").padding(.top, 12) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], spacing: 6) {
                ForEach(svc.names, id: \.self) { n in
                    Button { svc.run(n) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: svc.running == n ? "hourglass" : "bolt.fill").foregroundStyle(.orange)
                            Text(verbatim: n).lineLimit(1)
                        }.font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 7)
                        .rowCard()
                    }.buttonStyle(.plain)
                }
            }
        }.onAppear { svc.refresh() }
    }
}

struct AppsGrid: View {
    @ObservedObject var store = LauncherStore.shared
    @State private var dragging: String?

    var body: some View {
        ScrollView {
            if store.paths.isEmpty {
                Text("Pin the apps you open most with +, drag to reorder").font(.system(size: 11)).foregroundStyle(DS.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 96), spacing: DS.gap)], spacing: DS.gap) {
                ForEach(store.paths, id: \.self) { path in
                    VStack(spacing: 3) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 46, height: 46)
                        Text(((path as NSString).lastPathComponent as NSString).deletingPathExtension)
                            .font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.75).truncationMode(.middle).padding(.horizontal, 4)
                    }
                    .frame(maxWidth: .infinity).frame(height: 78)
                    .rowCard(radius: 10)
                    .onTapGesture { store.launch(path) }
                    .onDrag { dragging = path; return NSItemProvider(object: path as NSString) }
                    .onDrop(of: [.text], isTargeted: nil) { _ in
                        if let d = dragging { store.move(d, onto: path) }
                        return true
                    }
                    .contextMenu {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                        Button("Remove", role: .destructive) { store.remove(path) }
                    }
                }
                Button { store.add() } label: {
                    Image(systemName: "plus").font(.system(size: 15, weight: .medium)).foregroundStyle(DS.secondary).frame(maxWidth: .infinity).frame(height: 78)
                }.buttonStyle(.plain).rowCard(radius: 10).hoverTip(L("Add an app")).accessibilityLabel("Add an app")
            }
        }
    }
}

struct StocksTab: View {
    @ObservedObject var stocks = StocksService.shared
    @ObservedObject var model = NotchModel.shared
    @State private var symbol = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: DS.gap) {
                TextField("Add a symbol (AAPL, ^GSPC, BTC-USD…)", text: $symbol).pillField().focused($focused)
                    .onSubmit { stocks.add(symbol); symbol = "" }
                IconButton(symbol: "arrow.clockwise", label: L("Refresh")) { stocks.refresh() }
            }
            .onChange(of: focused) { model.pinnedOpen = $0 }
            if stocks.watchlist.isEmpty {
                EmptyState(symbol: "chart.line.uptrend.xyaxis", title: "Your watchlist is empty", message: "Type a symbol above and press Return")
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(stocks.watchlist, id: \.symbol) { w in row(w) }
                    }
                }
            }
        }
    }

    private func row(_ w: Watch) -> some View {
        let q = stocks.quotes[w.symbol]
        let up = (q?.change ?? 0) >= 0
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(w.symbol).font(.system(size: 12, weight: .semibold))
                    if stocks.pinned == w.symbol { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.orange) }
                    if w.above != nil { Image(systemName: "bell.fill").font(.system(size: 8)).foregroundStyle(.yellow) }
                }
                Text(LocalizedStringKey(q?.state ?? "…")).font(.system(size: 9)).foregroundStyle(.secondary)
            }.frame(width: 90, alignment: .leading)
            Sparkline(values: q?.series ?? [], color: up ? .green : .red).frame(height: 22)
            if let q {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.2f", q.price)).font(.system(size: 12, design: .monospaced))
                    Text(String(format: "%@%.2f%%", up ? "+" : "", q.change * 100)).font(.system(size: 10, design: .monospaced)).foregroundStyle(up ? .green : .red)
                }.frame(width: 80, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .rowCard()
        .onTapGesture { if let u = URL(string: "https://finance.yahoo.com/quote/\(w.symbol)") { NSWorkspace.shared.open(u) } }
        .contextMenu {
            Button(LocalizedStringKey(stocks.pinned == w.symbol ? "Unpin from pill" : "Pin to pill")) { stocks.pinned = stocks.pinned == w.symbol ? nil : w.symbol }
            Button("Alert at ±2%") { stocks.setAlert(w.symbol, percent: 2) }
            Button("Alert at ±5%") { stocks.setAlert(w.symbol, percent: 5) }
            Button("Clear alert") { stocks.setAlert(w.symbol, percent: nil) }
            Divider()
            Button("Remove", role: .destructive) { stocks.remove(w.symbol) }
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { g in
            if values.count > 1, let lo = values.min(), let hi = values.max() {
                Path { p in
                    for (i, v) in values.enumerated() {
                        let x = g.size.width * CGFloat(i) / CGFloat(values.count - 1)
                        let y = g.size.height * (1 - CGFloat(hi == lo ? 0.5 : (v - lo) / (hi - lo)))
                        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
                    }
                }.stroke(color, lineWidth: 1.5)
            }
        }
    }
}

struct AIUsageTab: View {
    @ObservedObject var usage = AIUsageService.shared
    @State private var selected = 0

    var body: some View {
        if usage.providers.isEmpty {
            EmptyState(symbol: "sparkles", title: LocalizedStringKey(usage.loading ? "Reading local logs…" : "No Claude Code, Codex, Gemini CLI, OpenCode or Cursor activity in the last 7 days"))
                .onAppear { usage.refresh() }
        } else {
            let p = usage.providers[min(selected, usage.providers.count - 1)]
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    if usage.providers.count > 1 {
                        PillSegmented(options: Array(usage.providers.indices), selection: $selected, tint: .purple.opacity(0.7)) { LocalizedStringKey(usage.providers[$0].name) }
                    } else { Label(p.name, systemImage: p.symbol).font(.system(size: 13, weight: .semibold)) }
                    if let pct = p.limitPercent {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Group { if (p.limitWindowMinutes ?? 300) >= 7 * 24 * 60 { Text("Monthly limit") } else { Text("\((p.limitWindowMinutes ?? 300) / 60)h limit") } }.foregroundStyle(.secondary); Spacer()
                                Text(String(format: "%.0f%%", pct)).font(.system(size: 12, weight: .semibold, design: .rounded))
                            }.font(.system(size: 11))
                            ProgressBar(value: pct, total: 100) { _ in }.tint(.orange)
                            if let r = p.limitResetsAt { Text("Resets \(r, style: .relative)").font(.system(size: 9)).foregroundStyle(.secondary) }
                        }.padding(8).rowCard()
                    }
                    if p.unit == "requests" {
                        stat("Used this month", p.today)
                        Text("Premium requests, read through the GitHub CLI").font(.system(size: 9)).foregroundStyle(.secondary)
                    } else {
                        stat("Last 5 hours", p.fiveHour)
                        stat("Today", p.today)
                        stat("7 days", p.week)
                    }
                    if p.unit != "requests", let d = p.lastActivity { Text("Last activity \(d, style: .relative) ago").font(.system(size: 9)).foregroundStyle(.secondary) }
                }.frame(width: 210, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        switch p.unit {
                        case "edits": Text("AI-written code edits per day")
                        case "requests": Text("Monthly budget: no daily history")
                        default: Text("Tokens per day (cache reads excluded)")
                        }
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                    let peak = max(p.days.map(\.tokens).max() ?? 1, 1)
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(p.days.enumerated()), id: \.offset) { _, d in
                            VStack(spacing: 3) {
                                Capsule().fill(Color.orange.opacity(d.tokens > 0 ? 1 : 0.15)).frame(width: 18, height: 6 + 60 * CGFloat(d.tokens) / CGFloat(peak))
                                Text(d.label).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .onAppear { usage.refresh() }
        }
    }

    private func stat(_ name: LocalizedStringKey, _ n: Int) -> some View {
        HStack { Text(name).foregroundStyle(.secondary); Spacer(); Text(AIUsageService.short(n)).font(.system(size: 14, weight: .semibold, design: .rounded)) }
            .font(.system(size: 11)).padding(.horizontal, 8).padding(.vertical, 3)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.rowRadius, style: .continuous))
    }
}

struct RemindersTab: View {
    @ObservedObject var rem = RemindersService.shared
    @ObservedObject var model = NotchModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        if !rem.authorized {
            EmptyState(symbol: "checklist", title: "Pillbox needs access to your reminders", actionTitle: "Allow", tint: .blue) { PermissionsCenter.shared.request(.reminders) }
        } else {
            VStack(spacing: DS.gap) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
                    TextField("Add a reminder, e.g. call mum tomorrow at 9am", text: $rem.draft).textFieldStyle(.plain).font(.system(size: 12)).focused($focused)
                        .onSubmit { rem.add() }
                        .onChange(of: focused) { model.pinnedOpen = $0 }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(DS.card, in: RoundedRectangle(cornerRadius: DS.rowRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.rowRadius, style: .continuous).strokeBorder(DS.hairline, lineWidth: 0.5))
                if rem.items.isEmpty {
                    EmptyState(symbol: "checkmark.circle", title: "Nothing to do", message: "Type a reminder above, with a date like tomorrow at 9am")
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(rem.items) { r in
                                HStack(spacing: 8) {
                                    Button { rem.complete(r) } label: { Image(systemName: "circle").foregroundStyle(DS.secondary) }.buttonStyle(.plain).accessibilityLabel("Complete")
                                    Text(r.title).lineLimit(1)
                                    Spacer()
                                    if let d = r.due { Text(d, format: .dateTime.day().month(.abbreviated).hour().minute()).foregroundStyle(r.overdue ? .red : DS.secondary) }
                                }
                                .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 5).rowCard()
                                .contextMenu { Button("Complete") { rem.complete(r) } }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct NotificationsTab: View {
    @ObservedObject var mirror = NotificationMirror.shared
    @State private var app: String?

    /// Bundle identifiers present, most recent first, for the filter chips.
    nonisolated static func apps(in items: [NotificationItem]) -> [String] {
        var seen = Set<String>(); return items.map(\.app).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    static func name(_ bundleID: String) -> String { BlockedAppsStore.name(bundleID) }

    var body: some View {
        Group {
            if let items = mirror.items, items.isEmpty {
                EmptyState(symbol: "bell.slash", title: "No notifications")
            } else if let items = mirror.items {
                let apps = Self.apps(in: items), shown = items.filter { app == nil || $0.app == app }
                VStack(spacing: DS.gap) {
                    if apps.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                FilterChip(symbol: "tray.full", label: L("All"), selected: app == nil, tint: .red) { app = nil }
                                ForEach(apps, id: \.self) { id in
                                    Button { app = app == id ? nil : id } label: {
                                        HStack(spacing: 4) {
                                            if let i = BlockedAppsStore.icon(id) { Image(nsImage: i).resizable().frame(width: 14, height: 14) }
                                            Text(verbatim: Self.name(id)).font(.system(size: 10, weight: .medium)).lineLimit(1)
                                            Text(verbatim: "\(items.filter { $0.app == id }.count)").font(.system(size: 9)).foregroundStyle(DS.secondary)
                                        }
                                        .padding(.horizontal, 8).frame(height: 22)
                                        .foregroundStyle(app == id ? Color.red : .white.opacity(0.75))
                                        .background(app == id ? Color.red.opacity(0.22) : .white.opacity(0.06), in: Capsule())
                                    }.buttonStyle(.plain).accessibilityAddTraits(app == id ? .isSelected : [])
                                }
                            }
                        }.frame(height: 22)
                    }
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(shown) { n in
                                HStack(spacing: 8) {
                                    if let i = BlockedAppsStore.icon(n.app) { Image(nsImage: i).resizable().frame(width: 22, height: 22) }
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack {
                                            Text(verbatim: n.title.isEmpty ? Self.name(n.app) : n.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                            Spacer()
                                            Text(n.date, style: .relative).font(.system(size: 9)).foregroundStyle(.secondary)
                                        }
                                        if !n.body.isEmpty { Text(verbatim: n.body).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2) }
                                        if n.app == MessageReply.app { SMSReplyField(sender: n.title) }
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
                                .rowCard()
                                .onTapGesture { if n.app != MessageReply.app { open(n.app) } }
                                .contextMenu {
                                    Button("Open the app") { open(n.app) }
                                    if let code = NotificationFeed.verificationCode(in: n.body) { Button(LocalizedStringKey(L("Copy code %@", code))) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) } }
                                    Button("Copy text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString([n.title, n.body].filter { !$0.isEmpty }.joined(separator: "\n"), forType: .string) }
                                }
                            }
                        }
                    }
                }
            } else {
                EmptyState(symbol: "bell.badge", title: "Reading notifications needs Full Disk Access", actionTitle: "Open Settings", tint: .red) { PermissionsCenter.shared.openSettings(.fullDisk) }
            }
        }
        .onAppear { mirror.refresh() }
    }

    private func open(_ bundleID: String) {
        guard let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: u, configuration: .init()); NotchModel.shared.collapse()
    }
}
