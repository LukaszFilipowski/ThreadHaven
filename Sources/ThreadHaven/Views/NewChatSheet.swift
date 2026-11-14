import SwiftUI

struct NewChatSheet: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let initialDirectory: String?

    @State private var directory = ""
    @State private var continueLast = false
    @State private var count = 1
    @State private var prompt = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Chat").font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Folder").font(.headline)
                HStack {
                    Picker("", selection: $directory) {
                        if !directory.isEmpty && !store.recentDirectories.contains(directory) {
                            Text(display(directory)).tag(directory)
                        }
                        ForEach(store.recentDirectories, id: \.self) { dir in
                            Text(display(dir)).tag(dir)
                        }
                    }
                    .labelsHidden()
                    Button(String(localized: "Choose…")) { chooseFolder() }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Chats side by side").font(.headline)
                Picker("", selection: $count) {
                    ForEach(1...SessionStore.maxPanes, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                Text("Each one is a separate, fresh chat in this folder. They open next to each other.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $continueLast) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue the previous thread")
                    Text("Runs claude --continue, so the most recent chat in this folder picks up where it left off. Leave it off to start a new, separate chat.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(count > 1)

            VStack(alignment: .leading, spacing: 6) {
                Text("First message (optional)").font(.headline)
                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            }

            HStack {
                Text(UserDefaults.standard.bool(forKey: Preferences.openInApp) ? String(localized: "Opens in ThreadHaven") : String(localized: "Opens in \(Preferences.terminal.name)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Start")) {
                    store.newChat(in: directory, continueLast: continueLast && count == 1, prompt: prompt, count: count)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(directory.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            directory = initialDirectory.flatMap { $0.isEmpty ? nil : $0 } ?? store.recentDirectories.first ?? ""
        }
    }

    private func display(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if !directory.isEmpty { panel.directoryURL = URL(fileURLWithPath: directory) }
        if panel.runModal() == .OK, let url = panel.url {
            directory = url.path
        }
    }
}
