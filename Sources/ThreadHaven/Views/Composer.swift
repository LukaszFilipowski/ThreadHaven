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

    private var canSend: Bool { TerminalBridge.canSend(to: session) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 54, maxHeight: 140)
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(8)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(dictation.isRecording ? Color.red : Color.secondary.opacity(0.25)))

            HStack(spacing: 8) {
                Button {
                    toggleDictation()
                } label: {
                    Label(dictation.isRecording ? String(localized: "Stop") : String(localized: "Dictate"),
                          systemImage: dictation.isRecording ? "stop.circle.fill" : "mic.fill")
                }
                .tint(dictation.isRecording ? .red : nil)
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .help(String(localized: "Dictate with on-device speech recognition (⇧⌘D)"))

                Button {
                    Task { await polish() }
                } label: {
                    if polishing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(String(localized: "Polish"), systemImage: "wand.and.stars")
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || polishing)
                .help(String(localized: "Turn a rough note into a clean prompt with Claude (\(polishModel))"))

                if let status = dictation.error ?? status {
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button {
                    sendNow()
                } label: {
                    Label(String(localized: "Send"), systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSend || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(canSend ? String(localized: "Send to the chat (⌘↩)") : unavailableHelp)
            }
        }
        .padding(12)
        .onDisappear { dictation.stop() }
    }

    private var placeholder: String {
        if canSend {
            return session.agent == .claude
                ? String(localized: "Type or dictate what Claude should do next…")
                : String(localized: "Type or dictate what Codex should do next…")
        }
        return String(localized: "Draft a prompt. Resume the chat to send it.")
    }

    private var unavailableHelp: String {
        String(localized: "Sending works for running chats in Terminal or iTerm2")
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
        dictation.stop()
        if store.send(text, to: session.id) {
            text = ""
            status = String(localized: "Sent")
        } else {
            status = String(localized: "Could not send. Check Automation permission for your terminal.")
        }
    }
}
