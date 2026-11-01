import SwiftUI

struct Composer: View {
    @Environment(SessionStore.self) private var store
    @AppStorage(Preferences.polishModel) private var polishModel = "haiku"
    @AppStorage("dictationLocale") private var dictationLocale = Locale.current.identifier
    let session: Session

    @State private var text = ""
    @State private var dictation = Dictation()
    @State private var baseText = ""
    @State private var polishing = false
    @State private var status: String?
    @FocusState private var focused: Bool

    private enum Mode {
        case terminal
        case resume
        case unavailable
    }

    private var mode: Mode {
        if TerminalBridge.canSend(to: session) { return .terminal }
        if !session.isLive && !session.cwd.isEmpty { return .resume }
        return .unavailable
    }

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                        .frame(minHeight: 22, maxHeight: 160)
                        .fixedSize(horizontal: false, vertical: true)
                        .onKeyPress(.return, phases: .down) { press in
                            guard !press.modifiers.contains(.shift) else { return .ignored }
                            sendNow()
                            return .handled
                        }
                    if text.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(dictation.isRecording ? Color.red : (focused ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.25)))
                )

                Button {
                    toggleDictation()
                } label: {
                    Image(systemName: dictation.isRecording ? "stop.circle.fill" : "mic")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(dictation.isRecording ? .red : nil)
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .help(String(localized: "Dictate with on-device speech recognition (⇧⌘D)"))

                Button {
                    Task { await polish() }
                } label: {
                    Group {
                        if polishing { ProgressView().controlSize(.small) } else { Image(systemName: "wand.and.stars") }
                    }
                    .frame(width: 18, height: 18)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isEmpty || polishing)
                .help(String(localized: "Turn a rough note into a clean prompt with Claude (\(polishModel))"))

                Button {
                    sendNow()
                } label: {
                    Label(sendTitle, systemImage: "arrow.up")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(mode == .unavailable || isEmpty)
                .help(sendHelp)
            }
            HStack(spacing: 6) {
                Text(hint)
                if let status = dictation.error ?? status {
                    Text("·")
                    Text(status)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear { focused = true }
        .onDisappear { dictation.stop() }
    }

    private var sendTitle: String {
        mode == .resume ? String(localized: "Resume & Send") : String(localized: "Send")
    }

    private var placeholder: String {
        session.agent == .claude
            ? String(localized: "Message Claude…")
            : String(localized: "Message Codex…")
    }

    private var isCommand: Bool { text.trimmingCharacters(in: .whitespaces).hasPrefix("/") }

    private var hint: String {
        if isCommand, mode != .unavailable {
            return String(localized: "Commands run in the chat's terminal. ThreadHaven switches to it so you can see the result.")
        }
        switch mode {
        case .terminal: return String(localized: "Return sends to the running chat in its terminal · Shift-Return for a new line")
        case .resume: return String(localized: "This chat is not running. Sending resumes it in a new terminal window with your message.")
        case .unavailable: return String(localized: "This chat runs in a terminal ThreadHaven cannot type into. Use Terminal or iTerm2 to send from here.")
        }
    }

    private var sendHelp: String {
        mode == .resume ? String(localized: "Resume the chat in a terminal with this message (⌘↩)") : String(localized: "Send to the chat (⌘↩)")
    }

    private func toggleDictation() {
        if dictation.isRecording {
            dictation.stop()
            return
        }
        status = nil
        baseText = text.isEmpty ? "" : text + " "
        dictation.start(locale: Locale(identifier: dictationLocale)) { partial in
            text = baseText + partial
        }
    }

    private func polish() async {
        dictation.stop()
        polishing = true
        status = nil
        defer { polishing = false }
        do {
            text = try await PromptPolisher.polish(text, model: polishModel)
        } catch {
            status = error.localizedDescription
        }
    }

    private func sendNow() {
        guard !isEmpty else { return }
        dictation.stop()
        switch mode {
        case .terminal:
            let command = isCommand
            if store.send(text, to: session.id) {
                text = ""
                status = String(localized: "Sent")
                if command { store.focus(session.id) }
            } else {
                status = String(localized: "Could not send. Check Automation permission for your terminal.")
            }
        case .resume:
            store.resume(session.id, prompt: text)
            text = ""
            status = String(localized: "Opened in a new terminal window")
        case .unavailable:
            break
        }
    }
}
