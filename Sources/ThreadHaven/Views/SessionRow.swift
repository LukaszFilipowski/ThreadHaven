import SwiftUI

struct SessionRow: View {
    let session: Session
    let shortcut: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusIcon(status: session.status)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(.body.weight(session.needsAttention ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if session.needsAttention {
                        Circle().fill(.orange).frame(width: 7, height: 7)
                    }
                    if let shortcut {
                        Text("⌘\(shortcut)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 6) {
                    if session.agent != .claude {
                        AgentBadge(agent: session.agent)
                    }
                    Text(session.project)
                    Text("·")
                    Text(session.lastActivity, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if session.meta != nil {
                    ContextBar(fraction: session.contextFraction)
                        .frame(height: 3)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

struct AgentBadge: View {
    let agent: Agent

    var body: some View {
        Text(agent.name)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
            .help(String(localized: "\(agent.name) session"))
    }
}

struct StatusIcon: View {
    let status: SessionStatus

    var body: some View {
        Group {
            if status == .working {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: status.symbol)
                    .foregroundStyle(color)
            }
        }
        .help(status.label)
    }

    private var color: Color {
        switch status {
        case .needsInput: .orange
        case .finished: .green
        case .working: .blue
        case .idle: .secondary
        case .closed: Color.secondary.opacity(0.6)
        }
    }
}

struct ContextBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Self.color(for: fraction))
                    .frame(width: max(2, geo.size.width * fraction))
            }
        }
    }

    static func color(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.5: .green
        case ..<0.75: .orange
        default: .red
        }
    }
}
