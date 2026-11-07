import SwiftUI

private let card = Color.white.opacity(0.08)

struct HomeTab: View {
    @ObservedObject var battery = BatteryService.shared
    @ObservedObject var stats = StatsService.shared
    @ObservedObject var calendar = CalendarService.shared
    @ObservedObject var caffeine = CaffeineService.shared
    @ObservedObject var timer = TimerService.shared
    @ObservedObject var audio = AudioControl.shared

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(ctx.date, format: .dateTime.hour().minute()).font(.system(size: 34, weight: .semibold, design: .rounded))
                }
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide)).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let e = calendar.next {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar").foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(e.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(e.start, style: e.start > Date() ? .relative : .time).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(card, in: RoundedRectangle(cornerRadius: 10))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    gauge("CPU", stats.cpu, .green)
                    gauge("RAM", stats.memory, .blue)
                    gauge("Batt", Double(battery.level) / 100, battery.level < 20 ? .red : .yellow, icon: battery.pluggedIn ? "bolt.fill" : nil)
                }
                HStack(spacing: 8) {
                    quick("cup.and.saucer.fill", "Awake", active: caffeine.active) { caffeine.toggle() }
                    quick("eyedropper", "Color") { Tools.pickColor() }
                    quick("camera.viewfinder", "Capture") { Tools.captureArea() }
                    quick("mic.slash.fill", "Mute", active: audio.micMuted) { audio.toggleMic() }
                    quick("timer", "Focus", active: timer.running) { timer.mode = .focus; timer.toggle() }
                }
            }.frame(width: 260)
        }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    private func gauge(_ name: String, _ v: Double, _ c: Color, icon: String? = nil) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(c.opacity(0.2), lineWidth: 5)
                Circle().trim(from: 0, to: v).stroke(c, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                if let icon { Image(systemName: icon).font(.system(size: 10)).foregroundStyle(c) }
                else { Text("\(Int(v * 100))").font(.system(size: 11, weight: .semibold, design: .rounded)) }
            }.frame(width: 46, height: 46)
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func quick(_ symbol: String, _ title: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(title).font(.system(size: 9))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(active ? Color.orange.opacity(0.35) : card, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}

struct MusicTab: View {
    @ObservedObject var music = MusicService.shared

    var body: some View {
        if !music.hasTrack {
            VStack(spacing: 6) {
                Image(systemName: "music.note.list").font(.system(size: 26)).foregroundStyle(.secondary)
                Text("Nothing playing").foregroundStyle(.secondary)
                Text("Start Spotify or Apple Music").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        } else {
            HStack(spacing: 14) {
                Group {
                    if let a = music.artwork { Image(nsImage: a).resizable() }
                    else { Rectangle().fill(card).overlay(Image(systemName: "music.note")) }
                }
                .frame(width: 118, height: 118).clipShape(RoundedRectangle(cornerRadius: 14))
                .onTapGesture { music.openPlayer() }

                VStack(alignment: .leading, spacing: 4) {
                    Text(music.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(music.artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    if let l = music.currentLyric {
                        Text(l).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                            .id(l).transition(.opacity).animation(.easeInOut(duration: 0.25), value: l)
                    }
                    Spacer(minLength: 0)
                    ProgressBar(value: music.position, total: music.duration) { music.seek(to: $0) }
                    HStack {
                        Text(TimerService.format(music.position)); Spacer(); Text(TimerService.format(music.duration))
                    }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    HStack(spacing: 26) {
                        Spacer()
                        Button { music.previous() } label: { Image(systemName: "backward.fill") }
                        Button { music.playPause() } label: { Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20)) }
                        Button { music.next() } label: { Image(systemName: "forward.fill") }
                        Spacer()
                    }.buttonStyle(.plain).font(.system(size: 16))
                }
            }
        }
    }
}

struct ProgressBar: View {
    let value: Double, total: Double
    let onSeek: (Double) -> Void
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white).frame(width: g.size.width * (total > 0 ? min(value / total, 1) : 0))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { onSeek(total * min(max($0.location.x / g.size.width, 0), 1)) })
        }.frame(height: 4)
    }
}

struct TimerTab: View {
    @ObservedObject var t = TimerService.shared

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 7)
                Circle().trim(from: 0, to: t.progress).stroke(Color.orange, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(t.display).font(.system(size: 22, weight: .semibold, design: .monospaced))
                    Text(t.mode.rawValue).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.frame(width: 118, height: 118)

            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $t.mode) { ForEach(TimerService.Mode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden()
                HStack(spacing: 8) {
                    Button { t.toggle() } label: { Label(t.running ? "Pause" : "Start", systemImage: t.running ? "pause.fill" : "play.fill") }
                        .buttonStyle(.borderedProminent).tint(.orange)
                    Button("Reset") { t.reset() }
                    if t.mode == .countdown { Button("Repeat") { t.repeatTimer() } }
                    Stepper(value: stepBinding, in: 1...180) { Text("\(stepBinding.wrappedValue) min").font(.system(size: 11)).monospacedDigit() }
                        .disabled(t.mode == .stopwatch || t.running)
                }.controlSize(.small)
                TextField("Name this timer", text: $t.label).textFieldStyle(.roundedBorder).controlSize(.small)
                HStack(spacing: 10) {
                    Toggle("Chain", isOn: $t.chain).toggleStyle(.checkbox).font(.system(size: 11))
                    Label("\(t.streak) day streak", systemImage: "flame.fill").font(.system(size: 11)).foregroundStyle(.orange)
                    Spacer()
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(t.week.enumerated()), id: \.offset) { _, d in
                            Capsule().fill(d.count > 0 ? Color.orange : .white.opacity(0.15))
                                .frame(width: 5, height: 4 + CGFloat(min(d.count, 6)) * 3)
                        }
                    }.frame(height: 24, alignment: .bottom).help("Focus sessions, last 7 days")
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
        VStack(spacing: 8) {
            HStack {
                TextField("Jot something down…", text: $store.draft).textFieldStyle(.roundedBorder).focused($focused)
                    .onSubmit { store.add() }
                if store.notes.contains(where: \.done) { Button("Clear done") { store.clearDone() }.controlSize(.small) }
            }
            .onChange(of: focused) { model.pinnedOpen = $0 }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.notes) { n in
                        HStack(spacing: 8) {
                            Button { store.toggle(n) } label: { Image(systemName: n.done ? "checkmark.circle.fill" : "circle") }.buttonStyle(.plain)
                            Text(n.text).strikethrough(n.done).foregroundStyle(n.done ? .secondary : .primary).lineLimit(2)
                            Spacer()
                            Button { store.remove(n) } label: { Image(systemName: "trash").foregroundStyle(.secondary) }.buttonStyle(.plain)
                        }
                        .font(.system(size: 12)).padding(.horizontal, 8).padding(.vertical, 5)
                        .background(card, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

struct ClipboardTab: View {
    @ObservedObject var clip = ClipboardService.shared
    @ObservedObject var model = NotchModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search text and screenshots", text: $clip.query).textFieldStyle(.plain).focused($focused)
                Button("Clear") { clip.clearUnpinned() }.controlSize(.small)
            }
            .padding(6).background(card, in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: focused) { model.pinnedOpen = $0 }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(clip.filtered) { item in ClipCard(item: item) }
                }
            }
        }
    }
}

struct ClipCard: View {
    let item: ClipItem
    @ObservedObject var clip = ClipboardService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content.frame(width: 130, height: 76, alignment: .topLeading).clipped()
            HStack(spacing: 6) {
                if item.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                Text(item.date, style: .relative).foregroundStyle(.secondary)
                Spacer()
                if let t = item.text, case .url(let u) = ClipboardService.kind(of: t) {
                    Button { NSWorkspace.shared.open(u) } label: { Image(systemName: "safari") }.buttonStyle(.plain)
                }
                if let t = item.text, case .email(let e) = ClipboardService.kind(of: t), let u = URL(string: "mailto:\(e)") {
                    Button { NSWorkspace.shared.open(u) } label: { Image(systemName: "envelope") }.buttonStyle(.plain)
                }
            }.font(.system(size: 9))
        }
        .padding(8).background(card, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { clip.copy(item); NotchModel.shared.show(Activity(symbol: "doc.on.doc.fill", title: "Copied", duration: 1.2)) }
        .onTapGesture(count: 2) { clip.paste(item) }
        .contextMenu {
            Button(item.pinned ? "Unpin" : "Pin") { clip.togglePin(item) }
            Button("Paste") { clip.paste(item) }
            Button("Delete") { clip.remove(item) }
        }
    }

    @ViewBuilder private var content: some View {
        if let img = clip.image(for: item) {
            Image(nsImage: img).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let t = item.text {
            switch ClipboardService.kind(of: t) {
            case .color(let c, let hex):
                VStack(alignment: .leading) { RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: c)).frame(height: 48); Text(hex.uppercased()).font(.system(size: 10, design: .monospaced)) }
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Text(t).font(.system(size: 10)).lineLimit(4)
                    if t.count > 140 { Text("\(t.count) chars · \(t.split(whereSeparator: \.isWhitespace).count) words").font(.system(size: 8)).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

struct ShelfTab: View {
    @ObservedObject var shelf = ShelfService.shared

    var body: some View {
        if shelf.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 26)).foregroundStyle(.secondary)
                Text("Drop files on the notch to stash them").foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 6) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) { ForEach(shelf.items) { ShelfCell(item: $0) } }
                }
                HStack(spacing: 8) {
                    let target = shelf.selection.isEmpty ? shelf.items : shelf.selected
                    Button("AirDrop") { shelf.airDrop(target) }
                    Button("Zip / Unzip") { shelf.zipOrUnzip(target) }
                    Button("Reveal") { shelf.reveal(target) }
                    Spacer()
                    Button("Clear") { shelf.clear() }
                }.controlSize(.small)
            }
        }
    }
}

struct ShelfCell: View {
    let item: ShelfItem
    @ObservedObject var shelf = ShelfService.shared

    var body: some View {
        let selected = shelf.selection.contains(item.id)
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path)).resizable().frame(width: 48, height: 48)
            Text(item.name).font(.system(size: 9)).lineLimit(2).multilineTextAlignment(.center).frame(width: 72)
        }
        .padding(6)
        .background(selected ? Color.accentColor.opacity(0.4) : card, in: RoundedRectangle(cornerRadius: 10))
        .onTapGesture { if selected { shelf.selection.remove(item.id) } else { shelf.selection.insert(item.id) } }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .contextMenu {
            Button("Remove") { shelf.remove([item.id]) }
            Button("Reveal in Finder") { shelf.reveal([item]) }
        }
    }
}

struct LauncherTab: View {
    @ObservedObject var store = LauncherStore.shared
    @State private var dragging: String?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 10), count: 8), spacing: 10) {
                ForEach(store.paths, id: \.self) { path in
                    VStack(spacing: 3) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 38, height: 38)
                        Text(((path as NSString).lastPathComponent as NSString).deletingPathExtension)
                            .font(.system(size: 9)).lineLimit(1)
                    }
                    .frame(width: 64, height: 60)
                    .contentShape(Rectangle())
                    .onTapGesture { store.launch(path) }
                    .onDrag { dragging = path; return NSItemProvider(object: path as NSString) }
                    .onDrop(of: [.text], isTargeted: nil) { _ in
                        if let d = dragging { store.move(d, before: path) }
                        return true
                    }
                    .contextMenu { Button("Remove") { store.remove(path) } }
                }
                Button { store.add() } label: {
                    Image(systemName: "plus").frame(width: 38, height: 38).background(card, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).frame(width: 64, height: 60)
            }
        }
    }
}
