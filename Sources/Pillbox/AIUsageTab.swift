import AppKit
import Foundation
import SwiftUI

/// What a provider's usage counts: AI-written edits, premium requests, or tokens (the default for local logs).
enum UsageUnit: String {
    case tokens, edits, requests
}

struct AIUsageTab: View {
    @ObservedObject var usage = AIUsageService.shared
    @State private var selected = 0
    /// The usual rate-limit window (5 hours), for a provider that does not give its own.
    private static let defaultLimitMinutes = 300

    var body: some View {
        if usage.providers.isEmpty {
            EmptyState(symbol: "sparkles", title: LocalizedStringKey(usage.loading ? "Reading local logs…" : "No Claude Code, Codex, Gemini CLI, OpenCode or Cursor activity in the last 7 days"))
                .onAppear { usage.refresh() }
        } else {
            let index = min(selected, usage.providers.count - 1)
            let provider = usage.providers[index]
            let unit = UsageUnit(rawValue: provider.unit) ?? .tokens
            HStack(alignment: .top, spacing: 14) {
                // One row per tool: a list scales to any number of tools, where a segmented control overflowed.
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(usage.providers.indices), id: \.self) { i in
                        providerRow(usage.providers[i], selected: i == index) { selected = i }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 150, alignment: .topLeading)
                detail(provider, unit: unit)
            }
            .onAppear { usage.refresh() }
        }
    }

    /// A tool in the list. An installed tool with no activity this week is dimmed on its own row, not the whole view.
    private func providerRow(_ p: ProviderUsage, selected: Bool, action: @escaping () -> Void) -> some View {
        let idle = p.unit != UsageUnit.requests.rawValue && p.week == 0
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: p.symbol).font(Design.caption).frame(width: 14)
                Text(verbatim: p.name).font(.system(size: 11, weight: selected ? .semibold : .regular)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if !idle { Text(verbatim: AIUsageService.short(p.week)).font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary) }
            }
            .foregroundStyle(.white.opacity(idle ? 0.45 : 1))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(selected ? Color.purple.opacity(0.35) : Design.card, in: RoundedRectangle(cornerRadius: Design.rowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The selected tool: its limit, its figures and its daily chart. Full strength, even when the tool is idle.
    private func detail(_ provider: ProviderUsage, unit: UsageUnit) -> some View {
        let windowMinutes = provider.limitWindowMinutes ?? Self.defaultLimitMinutes
        let peak = max(provider.days.map(\.tokens).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Label(provider.name, systemImage: provider.symbol).font(Design.titleStrong).lineLimit(1)
            if let percent = provider.limitPercent {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Group { if windowMinutes >= 7 * 24 * 60 { Text("Monthly limit") } else { Text("\(windowMinutes / 60)h limit") } }.foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", percent)).font(.system(size: 12, weight: .semibold, design: .rounded))
                    }.font(Design.label)
                    ProgressBar(value: percent, total: 100).tint(.orange)   // read-only: the limit is not ours to change
                    if let resets = provider.limitResetsAt { Text("Resets \(resets, style: .relative)").font(.system(size: 9)).foregroundStyle(.secondary) }
                }.padding(8).rowCard()
            }
            if unit == .requests {
                stat("Used this month", provider.today)
                Text("Premium requests, read through the GitHub CLI").font(.system(size: 9)).foregroundStyle(.secondary)
            } else {
                stat("Last 5 hours", provider.fiveHour)
                stat("Today", provider.today)
                stat("7 days", provider.week)
                if provider.week == 0 { Text("No activity in the last 7 days").font(Design.caption).foregroundStyle(.secondary) }
                if let lastActivity = provider.lastActivity { Text("Last activity \(lastActivity, style: .relative)").font(.system(size: 9)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if unit != .requests {
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        switch unit {
                        case .edits: Text("AI-written code edits per day")
                        case .requests: Text("Monthly budget: no daily history")
                        case .tokens: Text("Tokens per day (cache reads excluded)")
                        }
                    }.font(Design.caption).foregroundStyle(.secondary)
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(provider.days.enumerated()), id: \.offset) { _, day in
                            VStack(spacing: 3) {
                                Capsule().fill(Color.orange.opacity(day.tokens > 0 ? 1 : 0.15)).frame(width: 18, height: 6 + 60 * CGFloat(day.tokens) / CGFloat(peak))
                                Text(day.label).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func stat(_ name: LocalizedStringKey, _ n: Int) -> some View {
        HStack { Text(name).foregroundStyle(.secondary); Spacer(); Text(AIUsageService.short(n)).font(.system(size: 14, weight: .semibold, design: .rounded)) }
            .font(Design.label).padding(.horizontal, 8).padding(.vertical, 3)
            .background(Design.card, in: RoundedRectangle(cornerRadius: Design.rowRadius, style: .continuous))
    }
}
