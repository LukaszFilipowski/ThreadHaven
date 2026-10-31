import SwiftUI
import ThreadHavenCore

struct TokenInsightsView: View {
    let path: String
    let modified: Date?

    @State private var expanded = false
    @State private var stats: TokenStats?

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Group {
                if let stats {
                    content(stats)
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 6)
        } label: {
            Label(String(localized: "Token usage"), systemImage: "chart.bar.xaxis")
                .font(.callout.weight(.medium))
        }
        .task(id: TaskKey(expanded: expanded, modified: modified)) {
            guard expanded else { return }
            let url = URL(fileURLWithPath: path)
            stats = await Task.detached(priority: .userInitiated) { TokenStats.analyze(url: url) }.value
        }
    }

    private struct TaskKey: Equatable {
        let expanded: Bool
        let modified: Date?
    }

    private func content(_ stats: TokenStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    metric(String(localized: "Replies"), "\(stats.turns)")
                    metric(String(localized: "Start-up context"), short(stats.baselineContext))
                    metric(String(localized: "Peak context"), short(stats.peakContext))
                }
                GridRow {
                    metric(String(localized: "Context re-read"), short(stats.cacheReadTokens))
                    metric(String(localized: "Cache writes"), short(stats.cacheWriteTokens))
                    metric(String(localized: "Cold cache rebuilds"), "\(stats.coldRebuilds) · \(short(stats.coldRebuildTokens))")
                }
            }
            if !stats.heaviestToolResults.isEmpty {
                Text("Heaviest tool results")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(stats.heaviestToolResults.enumerated()), id: \.offset) { _, result in
                    HStack(spacing: 8) {
                        Text(result.tool).font(.caption.monospaced())
                        Text(result.label ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(short(result.tokens)).font(.caption.monospacedDigit())
                    }
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit())
        }
    }

    private func short(_ tokens: Int) -> String {
        tokens < 1000 ? "\(tokens)" : ContextGauge.short(tokens)
    }
}
