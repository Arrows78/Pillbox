import Foundation
import AppKit
import SwiftUI

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
        // Stopped after 30 seconds, so a hung network call or a keychain prompt cannot keep the tab loading forever.
        let r = ProcessRunner.run(gh, ["search", "prs", kind, "@me", "--state", "open", "--limit", "20", "--json", "title,url,number,repository,isDraft"], timeout: 30)
        return r.status == 0 ? parse(Data(r.output.utf8)) : nil
    }
}

/// Merge requests from GitLab through the glab CLI. A self-hosted server is named in the settings (GITLAB_HOST).
enum GitLabMRs {
    static let candidates = ["/opt/homebrew/bin/glab", "/usr/local/bin/glab", "/usr/bin/glab"]
    static var tool: String? { candidates.first { FileManager.default.isExecutableFile(atPath: $0) } }

    /// The project path and the merge request number from GitLab's `references.full` ("group/project!12").
    static func parse(_ data: Data) -> [PullRequest] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let title = d["title"] as? String, let url = d["web_url"] as? String, let n = d["iid"] as? Int,
                  url.hasPrefix("https://"), let full = (d["references"] as? [String: Any])?["full"] as? String else { return nil }
            let repo = full.components(separatedBy: "!").first ?? full
            return PullRequest(title: title, repo: repo, number: n, url: url, draft: d["draft"] as? Bool ?? false)
        }
    }

    /// `kind` is "--author" (authored) or "--review-requested" (reviewer), for the logged-in user. GitLab has no author
    /// filter that takes "me", so the authored list uses assignee, which is how a merge request is usually handed over.
    static func fetch(_ kind: String, host: String) -> [PullRequest]? {
        guard let glab = tool else { return nil }
        let filter = kind == "--review-requested" ? "--reviewer=@me" : "--assignee=@me"
        let env = host.isEmpty ? nil : ["GITLAB_HOST": host]
        let r = ProcessRunner.run(glab, ["mr", "list", filter, "--per-page", "20", "-F", "json"], timeout: 30, environment: env)
        return r.status == 0 ? parse(Data(r.output.utf8)) : nil
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
            let provider = Preferences.prProvider.value, host = Preferences.prGitLabHost.value
            let m: [PullRequest]?, r: [PullRequest]?
            if provider == "gitlab" {
                m = GitLabMRs.fetch("--author", host: host); r = GitLabMRs.fetch("--review-requested", host: host)
            } else {
                m = GitHubPRs.fetch("--author"); r = GitHubPRs.fetch("--review-requested")
            }
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
                if Preferences.prProvider.value == "gitlab" {
                    EmptyState(symbol: "arrow.triangle.pull", title: "Needs the GitLab CLI (glab), logged in", actionTitle: "Try again", tint: .teal) { svc.refresh() }
                } else {
                    EmptyState(symbol: "arrow.triangle.pull", title: "Needs the GitHub CLI (gh), logged in", actionTitle: "Try again", tint: .teal) { svc.refresh() }
                }
            } else if svc.loading && svc.mine.isEmpty && svc.review.isEmpty {
                EmptyState(symbol: "arrow.triangle.pull", title: "Loading pull requests…")
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
            HStack(spacing: 6) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Design.secondary)
                if !list.isEmpty { Text(verbatim: "\(list.count)").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 1).background(Design.card, in: Capsule()) }
                Spacer()
                if svc.loading { ProgressView().controlSize(.mini) }
            }.frame(height: 16)
            ScrollView {
                VStack(spacing: 4) {
                    if list.isEmpty && !svc.loading {
                        Label("Nothing open", systemImage: "checkmark.circle").font(.system(size: 11)).foregroundStyle(Design.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: Design.rowRadius, style: .continuous).strokeBorder(Design.hairline, style: StrokeStyle(lineWidth: 1, dash: [3])))
                    }
                    ForEach(list) { pr in
                        Button { if let u = URL(string: pr.url) { NSWorkspace.shared.open(u) } } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: pr.title).font(.system(size: 12)).lineLimit(1)
                                Text(verbatim: "\(pr.repo) #\(pr.number)" + (pr.draft ? " · draft" : "")).font(.system(size: 9)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 5)
                            .rowCard()
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button("Open on GitHub") { if let u = URL(string: pr.url) { NSWorkspace.shared.open(u) } }
                            Button("Copy link") { TextCopy.copy(pr.url) }
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity)
    }
}

// MARK: Edge volume and brightness bar
