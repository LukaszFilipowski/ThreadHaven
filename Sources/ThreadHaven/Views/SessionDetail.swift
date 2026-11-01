import SwiftUI
import ThreadHavenCore

struct SessionDetail: View {
    @Environment(SessionStore.self) private var store
    let session: Session
    @State private var messages: [ChatMessage] = []
    @State private var loading = true
    @State private var atBottom = true
    @State private var showInsights = false

    static let coldCacheWarningTokens = 50_000

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack(alignment: .bottom) {
                transcript
                if !atBottom, !messages.isEmpty {
                    Button {
                        jumpToLatest = true
                    } label: {
                        Label(String(localized: "Latest"), systemImage: "arrow.down")
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .shadow(radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                }
            }
            Divider()
            Composer(session: session)
        }
        .task(id: session.meta?.modified) {
            await loadMessages()
        }
    }

    @State private var jumpToLatest = false
    @State private var scrolledInitially = false

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProjectBar(session: session)
            HStack(alignment: .center, spacing: 12) {
                Text(session.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                StatusPill(session: session)
            }
            if let msg = session.live?.message, session.status == .needsInput {
                Label(msg, systemImage: "hand.raised.fill")
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if session.isCacheCold(at: context.date), let meta = session.meta, meta.contextTokens >= Self.coldCacheWarningTokens {
                    ColdCacheBanner(session: session, tokens: meta.contextTokens)
                }
            }
            if case .failed(let message) = store.handoffs[session.id] {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 14) {
                if let meta = session.meta {
                    ContextGauge(tokens: meta.contextTokens, window: meta.contextWindow)
                    if let model = meta.model {
                        Text(model).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if session.agent == .claude {
                        Button {
                            showInsights.toggle()
                        } label: {
                            Label(String(localized: "Token usage"), systemImage: "chart.bar.xaxis")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .popover(isPresented: $showInsights, arrowEdge: .bottom) {
                            TokenInsightsView(path: meta.path, modified: meta.modified, startExpanded: true)
                                .padding(14)
                                .frame(width: 420)
                        }
                    }
                }
                Spacer(minLength: 8)
                actions
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 6) {
            if session.isLive {
                Button {
                    store.focus(session.id)
                } label: {
                    Label(String(localized: "Terminal"), systemImage: "terminal")
                }
                .help(String(localized: "Go to Terminal"))
                Button {
                    store.compact(session.id)
                } label: {
                    Label(String(localized: "Compact"), systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .disabled(!TerminalBridge.canCompact(session))
                .help(String(localized: "Sends /compact to this chat"))
            } else {
                Button {
                    store.resume(session.id)
                } label: {
                    Label(String(localized: "Resume"), systemImage: "play.fill")
                }
                .disabled(session.cwd.isEmpty)
                .help(String(localized: "Resume in Terminal"))
            }
            HandoffButton(session: session)
            Menu {
                SessionActions(session: session)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .controlSize(.small)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if messages.isEmpty && !loading {
                        Text("No messages to show yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(TranscriptItem.group(messages)) { item in
                        TranscriptItemView(item: item, agent: session.agent)
                            .frame(maxWidth: 820)
                            .frame(maxWidth: .infinity)
                    }
                    if session.status == .working {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(session.agent == .claude ? String(localized: "Claude is working…") : String(localized: "Codex is working…"))
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .frame(maxWidth: 820, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            .defaultScrollAnchor(.bottom)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 60
            } action: { _, isAtBottom in
                atBottom = isAtBottom
            }
            .onChange(of: messages.last?.id) { _, _ in
                guard atBottom || !scrolledInitially else { return }
                scrolledInitially = true
                Task { @MainActor in
                    for _ in 0..<3 {
                        try? await Task.sleep(for: .milliseconds(60))
                        proxy.scrollTo(Self.bottomID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: jumpToLatest) { _, jump in
                guard jump else { return }
                withAnimation { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                jumpToLatest = false
            }
        }
    }

    private static let bottomID = "transcript-bottom"

    private func loadMessages() async {
        guard let path = session.meta?.path ?? session.live?.transcriptPath else {
            loading = false
            return
        }
        let agent = session.agent
        let result = await Task.detached(priority: .userInitiated) {
            agent == .codex ? CodexReader.recentMessages(path: path, limit: 120) : TranscriptReader.recentMessages(path: path, limit: 120)
        }.value
        messages = result
        loading = false
    }
}

struct ProjectBar: View {
    let session: Session

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.accentColor)
            Text(session.project)
                .font(.headline)
            if let branch = session.meta?.gitBranch, branch != "HEAD" {
                Label(branch, systemImage: "arrow.triangle.branch")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            AgentBadge(agent: session.agent)
            Text(displayPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .help(session.cwd)
    }

    private var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return session.cwd.hasPrefix(home) ? "~" + session.cwd.dropFirst(home.count) : session.cwd
    }
}

enum TranscriptItem: Identifiable {
    case message(ChatMessage)
    case tools([ChatMessage])

    var id: String {
        switch self {
        case .message(let message): message.id
        case .tools(let calls): "tools-" + (calls.first?.id ?? "")
        }
    }

    static func group(_ messages: [ChatMessage]) -> [TranscriptItem] {
        var items: [TranscriptItem] = []
        for message in messages {
            if message.role == .tool, case .tools(let calls)? = items.last {
                items[items.count - 1] = .tools(calls + [message])
            } else {
                items.append(message.role == .tool ? .tools([message]) : .message(message))
            }
        }
        return items
    }
}

struct TranscriptItemView: View {
    let item: TranscriptItem
    let agent: Agent

    var body: some View {
        switch item {
        case .message(let message) where message.role == .user:
            HStack {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: 4) {
                    CollapsibleText(text: message.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                    if let date = message.date {
                        Text(date, style: .time).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        case .message(let message) where message.role == .output:
            Text(message.text)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        case .message(let message):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .foregroundStyle(Color.accentColor)
                    Text(agent.name).font(.caption.weight(.semibold))
                    if let date = message.date {
                        Text(date, style: .time).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                CollapsibleText(text: message.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .tools(let calls):
            ToolCallsView(calls: calls)
        }
    }
}

struct ToolCallsView: View {
    let calls: [ChatMessage]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                    Image(systemName: "wrench.and.screwdriver")
                    Text(summary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(calls) { call in
                        Text(call.text)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
                .padding(.leading, 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summary: String {
        let first = calls.first?.text ?? ""
        return calls.count == 1 ? first : String(localized: "\(calls.count) tool calls · \(first)")
    }
}

struct CollapsibleText: View {
    let text: String
    @State private var expanded = false

    private static let lineLimit = 14
    private static let characterLimit = 1_400

    private var isLong: Bool {
        text.count > Self.characterLimit || text.components(separatedBy: "\n").count > Self.lineLimit
    }

    private var preview: String {
        let lines = text.components(separatedBy: "\n").prefix(Self.lineLimit).joined(separator: "\n")
        return String(lines.prefix(Self.characterLimit)) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MarkdownText(text: isLong && !expanded ? preview : text)
            if isLong {
                Button(expanded ? String(localized: "Show less") : String(localized: "Show more")) {
                    expanded.toggle()
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
    }
}

struct MarkdownText: View {
    let text: String

    enum Block {
        case paragraph(String)
        case heading(Int, String)
        case code(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(Self.inline(text))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .heading(let level, let text):
                    Text(Self.inline(text))
                        .font(level <= 2 ? .title3.weight(.semibold) : .headline)
                        .padding(.top, 4)
                        .textSelection(.enabled)
                case .code(let code):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(code)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
                }
            }
        }
        .font(.body)
    }

    static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        func flush() {
            let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph = []
        }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
            } else if code != nil {
                code?.append(line)
            } else if trimmed.isEmpty {
                flush()
            } else if let hashes = trimmed.firstIndex(where: { $0 != "#" }), trimmed.hasPrefix("#"),
                      trimmed[hashes] == " ", trimmed.distance(from: trimmed.startIndex, to: hashes) <= 6 {
                flush()
                blocks.append(.heading(trimmed.distance(from: trimmed.startIndex, to: hashes), String(trimmed[hashes...]).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(line)
            }
        }
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var result = try? AttributedString(markdown: text, options: options) else { return AttributedString(text) }
        for run in result.runs where run.link != nil && !["http", "https"].contains(run.link?.scheme?.lowercased()) {
            result[run.range].link = nil
        }
        return result
    }
}

struct HandoffButton: View {
    @Environment(SessionStore.self) private var store
    let session: Session

    var body: some View {
        let running = store.handoffs[session.id] == .running
        Button {
            store.handOff(session.id)
        } label: {
            if running {
                ProgressView().controlSize(.small)
            } else {
                Label(String(localized: "Hand Off"), systemImage: "arrow.uturn.right.circle")
            }
        }
        .disabled(running || session.cwd.isEmpty || session.agent != .claude)
        .help(String(localized: "Writes a handoff note with a cheap model and continues in a fresh chat"))
    }
}

struct ColdCacheBanner: View {
    @Environment(SessionStore.self) private var store
    let session: Session
    let tokens: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "snowflake")
                .foregroundStyle(.blue)
            Text("The prompt cache of this chat has expired, so the next message re-reads all \(ContextGauge.short(tokens)) tokens at full price. Compact it or hand off to a fresh chat first.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if TerminalBridge.canCompact(session) {
                Button(String(localized: "Compact")) { store.compact(session.id) }
            }
            HandoffButton(session: session)
        }
        .padding(10)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StatusPill: View {
    let session: Session

    var body: some View {
        HStack(spacing: 6) {
            StatusIcon(status: session.status)
            Text(session.status.label)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.6), in: Capsule())
    }
}

struct ContextGauge: View {
    let tokens: Int
    let window: Int

    var body: some View {
        let fraction = window > 0 ? min(1, Double(tokens) / Double(window)) : 0
        HStack(spacing: 8) {
            ContextBar(fraction: fraction).frame(width: 90, height: 6)
            Text("\(Int(fraction * 100))% · \(Self.short(tokens)) / \(Self.short(window))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .help(String(localized: "Context window usage of the last reply"))
    }

    static func short(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000) : "\(n / 1000)k"
    }
}

