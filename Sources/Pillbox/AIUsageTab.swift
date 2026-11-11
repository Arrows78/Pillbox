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
            let provider = usage.providers[min(selected, usage.providers.count - 1)]
            let unit = UsageUnit(rawValue: provider.unit) ?? .tokens
            let windowMinutes = provider.limitWindowMinutes ?? Self.defaultLimitMinutes
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    if usage.providers.count > 1 {
                        PillSegmented(options: Array(usage.providers.indices), selection: $selected, tint: .purple.opacity(0.7)) { LocalizedStringKey(usage.providers[$0].name) }
                    } else { Label(provider.name, systemImage: provider.symbol).font(.system(size: 13, weight: .semibold)) }
                    if let percent = provider.limitPercent {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Group { if windowMinutes >= 7 * 24 * 60 { Text("Monthly limit") } else { Text("\(windowMinutes / 60)h limit") } }.foregroundStyle(.secondary); Spacer()
                                Text(String(format: "%.0f%%", percent)).font(.system(size: 12, weight: .semibold, design: .rounded))
                            }.font(.system(size: 11))
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
                    }
                    if unit != .requests, provider.week == 0 {
                        Text("No activity in the last 7 days").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if unit != .requests, let lastActivity = provider.lastActivity { Text("Last activity \(lastActivity, style: .relative)").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
                .frame(width: 210, alignment: .leading)
                // Installed but idle this week: the figures are zero, so the column recedes instead of looking broken.
                .opacity(provider.week == 0 && unit != .requests ? 0.45 : 1)
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        switch unit {
                        case .edits: Text("AI-written code edits per day")
                        case .requests: Text("Monthly budget: no daily history")
                        case .tokens: Text("Tokens per day (cache reads excluded)")
                        }
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                    let peak = max(provider.days.map(\.tokens).max() ?? 1, 1)
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(provider.days.enumerated()), id: \.offset) { _, day in
                            VStack(spacing: 3) {
                                Capsule().fill(Color.orange.opacity(day.tokens > 0 ? 1 : 0.15)).frame(width: 18, height: 6 + 60 * CGFloat(day.tokens) / CGFloat(peak))
                                Text(day.label).font(.system(size: 9)).foregroundStyle(.secondary)
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
            .background(Design.card, in: RoundedRectangle(cornerRadius: Design.rowRadius, style: .continuous))
    }
}
