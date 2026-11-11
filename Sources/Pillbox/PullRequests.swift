import Foundation
import AppKit
import SwiftUI

/// The state of a pull request's checks (CI): none when there are no checks.
enum PRChecks: Equatable { case none, passing, pending, failing }

/// The review state of a pull request, from GitHub's review decision.
enum PRReview: Equatable { case none, required, approved, changes }

struct PullRequest: Identifiable, Equatable {
    var id: String { url }
    let title: String
    let repo: String
    let number: Int
    let url: String
    let draft: Bool
    var checks: PRChecks = .none
    var review: PRReview = .none
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
    /// The checks and the review state from `gh pr view --json statusCheckRollup,reviewDecision`. Each check is a run
    /// (status and conclusion) or a commit status (state); any failure wins over pending, pending over passing.
    static func summarize(_ data: Data) -> (checks: PRChecks, review: PRReview)? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let rollup = obj["statusCheckRollup"] as? [[String: Any]] ?? []
        let failing: Set<String> = ["FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "ERROR"]
        let pending: Set<String> = ["IN_PROGRESS", "QUEUED", "PENDING", "WAITING", "REQUESTED", "EXPECTED"]
        var checks = PRChecks.none
        if !rollup.isEmpty {
            let states = rollup.map { c -> (String, String) in
                let conclusion = (c["conclusion"] as? String) ?? ""
                let status = (c["status"] as? String) ?? (c["state"] as? String) ?? ""
                return (conclusion, status)
            }
            if states.contains(where: { failing.contains($0.0) || failing.contains($0.1) }) { checks = .failing }
            else if states.contains(where: { pending.contains($0.1) || ($0.0.isEmpty && $0.1.isEmpty) }) { checks = .pending }
            else { checks = .passing }
        }
        let review: PRReview
        switch obj["reviewDecision"] as? String ?? "" {
        case "APPROVED": review = .approved
        case "CHANGES_REQUESTED": review = .changes
        case "REVIEW_REQUIRED": review = .required
        default: review = .none
        }
        return (checks, review)
    }

    /// Reads the checks and review state of each listed pull request, a few at a time, and returns the list with them.
    static func withDetails(_ list: [PullRequest], limit: Int = 12) -> [PullRequest] {
        guard let gh = tool else { return list }
        var out = list
        let indices = Array(out.indices.prefix(limit))
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: indices.count) { k in
            let i = indices[k]
            let r = ProcessRunner.run(gh, ["pr", "view", list[i].url, "--json", "statusCheckRollup,reviewDecision"], timeout: 30)
            guard r.status == 0, let s = summarize(Data(r.output.utf8)) else { return }
            lock.lock(); out[i].checks = s.checks; out[i].review = s.review; lock.unlock()
        }
        return out
    }

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

    /// The message when nothing can be read, for the services turned on in Settings.
    var needsSetup: LocalizedStringKey {
        switch (Preferences.prUseGitHub.value, Preferences.prUseGitLab.value) {
        case (false, false): "Turn on GitHub or GitLab in Settings"
        case (true, true): "Needs the GitHub (gh) or GitLab (glab) CLI, logged in"
        case (false, true): "Needs the GitLab CLI (glab), logged in"
        default: "Needs the GitHub CLI (gh), logged in"
        }
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async {
            // Each enabled service contributes its lists; GitHub's pull requests get their checks and review state,
            // GitLab's are not read for those yet. The tab fails only when every enabled service failed.
            var mine: [PullRequest] = [], review: [PullRequest] = []
            var anyEnabled = false, allFailed = true
            if Preferences.prUseGitHub.value {
                anyEnabled = true
                let m = GitHubPRs.fetch("--author"), r = GitHubPRs.fetch("--review-requested")
                mine += GitHubPRs.withDetails(m ?? []); review += GitHubPRs.withDetails(r ?? [])
                if m != nil || r != nil { allFailed = false }
            }
            if Preferences.prUseGitLab.value {
                anyEnabled = true
                let host = Preferences.prGitLabHost.value
                let m = GitLabMRs.fetch("--author", host: host), r = GitLabMRs.fetch("--review-requested", host: host)
                mine += m ?? []; review += r ?? []
                if m != nil || r != nil { allFailed = false }
            }
            let failed = !anyEnabled || allFailed
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.loading = false; self.failed = failed
                    self.mine = mine; self.review = review
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
                EmptyState(symbol: "arrow.triangle.pull", title: svc.needsSetup, actionTitle: "Try again", tint: Tab.pulls.tint) { svc.refresh() }
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
                SectionHeader(title).fixedSize()
                if !list.isEmpty { Text(verbatim: "\(list.count)").font(Design.captionStrong).padding(.horizontal, 6).padding(.vertical, 1).background(Design.card, in: Capsule()) }
                Spacer()
                if svc.loading { ProgressView().controlSize(.mini) }
            }.frame(height: 16)
            ScrollView {
                VStack(spacing: 4) {
                    if list.isEmpty && !svc.loading {
                        Label("Nothing open", systemImage: "checkmark.circle").font(Design.label).foregroundStyle(Design.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: Design.rowRadius, style: .continuous).strokeBorder(Design.hairline, style: StrokeStyle(lineWidth: 1, dash: [3])))
                    }
                    ForEach(Self.byRepo(list), id: \.repo) { group in
                        SectionHeader(Text(verbatim: group.repo)).lineLimit(1).truncationMode(.middle).padding(.top, 2)
                    ForEach(group.items) { pr in
                        Button { if let u = URL(string: pr.url) { NSWorkspace.shared.open(u) } } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: pr.title).font(Design.body).lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(verbatim: "#\(pr.number)" + (pr.draft ? " · draft" : "")).font(.system(size: 9)).foregroundStyle(.secondary)
                                    PRStateChips(checks: pr.checks, review: pr.review)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 5)
                            .rowCard()
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button("Open in browser") { if let u = URL(string: pr.url) { NSWorkspace.shared.open(u) } }
                            Button("Copy link") { TextCopy.copy(pr.url) }
                        }
                    }
                    }
                }
            }
        }.frame(maxWidth: .infinity)
    }

    /// The list split by repository, in the order each repository first appears.
    static func byRepo(_ list: [PullRequest]) -> [(repo: String, items: [PullRequest])] {
        var order: [String] = [], groups: [String: [PullRequest]] = [:]
        for pr in list {
            if groups[pr.repo] == nil { order.append(pr.repo) }
            groups[pr.repo, default: []].append(pr)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }
}

// MARK: Edge volume and brightness bar

/// The checks and review state of a pull request, as two small symbols. Nothing is drawn for a state that is not known.
struct PRStateChips: View {
    let checks: PRChecks
    let review: PRReview

    var body: some View {
        HStack(spacing: 4) {
            switch checks {
            case .passing: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failing: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .pending: Image(systemName: "clock.fill").foregroundStyle(.orange)
            case .none: EmptyView()
            }
            switch review {
            case .approved: Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            case .changes: Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(.red)
            case .required: Image(systemName: "eye.fill").foregroundStyle(.secondary)
            case .none: EmptyView()
            }
        }
        .font(.system(size: 9))
    }
}
