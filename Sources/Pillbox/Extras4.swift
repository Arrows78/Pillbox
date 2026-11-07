import AppKit
import SwiftUI

// MARK: Usage limit alert

/// Warns once per limit window when the reported usage crosses a threshold.
struct UsageAlertState {
    private var alerted = Set<String>()

    /// `windowKey` identifies the limit window (provider and reset time), so a new window can alert again.
    mutating func shouldAlert(percent: Double, threshold: Double, windowKey: String) -> Bool {
        guard percent >= threshold, !alerted.contains(windowKey) else { return false }
        alerted.insert(windowKey)
        return true
    }
}

extension AIUsageService {
    func checkAlerts(_ list: [ProviderUsage]) {
        let threshold = UserDefaults.standard.integer(forKey: "usageAlert")
        guard threshold > 0 else { return }
        for p in list {
            guard let pct = p.limitPercent, let reset = p.limitResetsAt else { continue }
            if alertState.shouldAlert(percent: pct, threshold: Double(threshold), windowKey: "\(p.name)|\(Int(reset.timeIntervalSince1970))") {
                NotchModel.shared.show(Activity(symbol: "gauge.with.dots.needle.67percent", title: L("%@ limit at %d%%", p.name, Int(pct)),
                                                subtitle: L("Resets %@", reset.formatted(date: .omitted, time: .shortened)), tint: .orange, duration: 8))
            }
        }
    }
}

// MARK: GitHub pull requests (through the `gh` command, which holds your login)

struct PullRequest: Identifiable, Equatable {
    var id: String { url }
    let title: String
    let repo: String
    let number: Int
    let url: String
    let draft: Bool
}

enum GitHubPRs {
    static let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
    static var tool: String? { candidates.first { FileManager.default.isExecutableFile(atPath: $0) } }

    static func parse(_ data: Data) -> [PullRequest] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let title = d["title"] as? String, let url = d["url"] as? String, let n = d["number"] as? Int,
                  url.hasPrefix("https://"), let repo = (d["repository"] as? [String: Any])?["nameWithOwner"] as? String else { return nil }
            return PullRequest(title: title, repo: repo, number: n, url: url, draft: d["isDraft"] as? Bool ?? false)
        }
    }

    /// `kind` is "--author" or "--review-requested"; always for the logged-in user.
    static func fetch(_ kind: String) -> [PullRequest]? {
        guard let gh = tool else { return nil }
        let p = Process(); p.executableURL = URL(fileURLWithPath: gh)
        p.arguments = ["search", "prs", kind, "@me", "--state", "open", "--limit", "20", "--json", "title,url,number,repository,isDraft"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return p.terminationStatus == 0 ? parse(data) : nil
    }
}

@MainActor
final class PullRequestsService: ObservableObject {
    static let shared = PullRequestsService()
    @Published private(set) var mine: [PullRequest] = []
    @Published private(set) var review: [PullRequest] = []
    @Published private(set) var failed = false
    @Published private(set) var loading = false

    func refresh() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async {
            let m = GitHubPRs.fetch("--author"), r = GitHubPRs.fetch("--review-requested")
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.loading = false; self.failed = m == nil || r == nil
                    self.mine = m ?? []; self.review = r ?? []
                }
            }
        }
    }
}

struct PullRequestsTab: View {
    @ObservedObject var svc = PullRequestsService.shared

    var body: some View {
        Group {
            if svc.failed {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.pull").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("Needs the GitHub CLI (gh), logged in").foregroundStyle(.secondary)
                    Button("Try again") { svc.refresh() }.controlSize(.small)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    column("To review", svc.review)
                    column("Yours", svc.mine)
                }
            }
        }.onAppear { svc.refresh() }
    }

    private func column(_ title: LocalizedStringKey, _ list: [PullRequest]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 4) {
                    if list.isEmpty { Text(svc.loading ? "…" : "Nothing open").font(.system(size: 11)).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading) }
                    ForEach(list) { pr in
                        Button { if let u = URL(string: pr.url) { NSWorkspace.shared.open(u) } } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: pr.title).font(.system(size: 12)).lineLimit(1)
                                Text(verbatim: "\(pr.repo) #\(pr.number)" + (pr.draft ? " · draft" : "")).font(.system(size: 9)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.frame(maxWidth: .infinity)
    }
}

// MARK: Edge volume and brightness bar

/// A slim bar on the right edge of the screen instead of an island, for the "Edge bar" style.
@MainActor
final class EdgeHUD {
    static let shared = EdgeHUD()
    private var panel: NSPanel?
    private let model = EdgeModel()
    private var hideTask: Task<Void, Never>?

    nonisolated static let barSize = CGSize(width: 44, height: 200)

    /// Height of the filled part for a level, clamped to the bar.
    nonisolated static func fill(for level: Double, trackHeight: CGFloat) -> CGFloat { trackHeight * CGFloat(min(max(level, 0), 1)) }

    func show(symbol: String, level: Double) {
        guard let sc = NotchModel.shared.geometry.screen ?? NSScreen.main else { return }
        model.symbol = symbol; model.level = level
        let p = panel ?? {
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: Self.barSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.ignoresMouseEvents = true
            p.level = .screenSaver; p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: EdgeBarView(model: model))
            panel = p; return p
        }()
        p.setFrameOrigin(NSPoint(x: sc.frame.maxX - Self.barSize.width - 14, y: sc.frame.midY - Self.barSize.height / 2))
        p.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }
}

@MainActor
final class EdgeModel: ObservableObject {
    @Published var symbol = "speaker.wave.2.fill"
    @Published var level = 0.0
}

struct EdgeBarView: View {
    @ObservedObject var model: EdgeModel
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { g in
                ZStack(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white).frame(height: EdgeHUD.fill(for: model.level, trackHeight: g.size.height))
                }
            }.frame(width: 8)
            Image(systemName: model.symbol).font(.system(size: 14)).foregroundStyle(.white)
        }
        .padding(.vertical, 12).frame(width: EdgeHUD.barSize.width, height: EdgeHUD.barSize.height)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 22))
        .environment(\.colorScheme, .dark)
    }
}
