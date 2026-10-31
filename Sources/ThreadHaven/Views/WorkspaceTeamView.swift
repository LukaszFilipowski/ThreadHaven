import SwiftUI

struct WorkspaceTeamView: View {
    let project: String
    let refreshID: UUID
    @State private var setup = TeamSetup()
    @State private var loading = false
    @State private var addingMarketplace = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(16)
            Divider()
            list
        }
        .task(id: "\(project)|\(refreshID)") { await load() }
        .sheet(isPresented: $addingMarketplace) {
            AddTeamMarketplaceSheet(project: project) {
                Task { await load() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("Share skills with your team through Claude Code plugin marketplaces. What the project's .claude/settings.json declares reaches everyone who clones the repository.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(String(localized: "Add Team Marketplace…")) {
                addingMarketplace = true
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var list: some View {
        let projectPlugins = setup.plugins.filter { $0.origin == .project }
        let localPlugins = setup.plugins.filter { $0.origin == .local }
        return List {
            if !setup.marketplaces.isEmpty {
                Section {
                    ForEach(setup.marketplaces) { TeamMarketplaceRow(marketplace: $0) }
                } header: {
                    Label(String(localized: "Marketplaces"), systemImage: "storefront")
                }
            }
            if !projectPlugins.isEmpty {
                Section {
                    ForEach(projectPlugins) { TeamPluginRow(plugin: $0) }
                } header: {
                    Label(String(localized: "Plugins set for the team"), systemImage: "person.3")
                }
            }
            if !localPlugins.isEmpty {
                Section {
                    ForEach(localPlugins) { TeamPluginRow(plugin: $0) }
                } header: {
                    Label(String(localized: "Local overrides"), systemImage: "laptopcomputer")
                }
            }
        }
        .overlay {
            if loading && setup.marketplaces.isEmpty && setup.plugins.isEmpty {
                ProgressView()
            } else if setup.marketplaces.isEmpty && setup.plugins.isEmpty {
                ContentUnavailableView(
                    String(localized: "No team setup yet"),
                    systemImage: "person.3",
                    description: Text("This project declares no marketplaces or plugins.")
                )
            }
        }
    }

    private func load() async {
        loading = true
        let url = URL(fileURLWithPath: project, isDirectory: true)
        let result = await Task.detached(priority: .userInitiated) { TeamMarketplaces.scan(project: url) }.value
        guard !Task.isCancelled else { return }
        setup = result
        loading = false
    }
}

struct TeamMarketplaceRow: View {
    let marketplace: TeamMarketplace

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(marketplace.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(marketplace.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            Text(marketplace.origin.title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(marketplace.origin.explanation)
    }
}

struct TeamPluginRow: View {
    let plugin: TeamPlugin

    var body: some View {
        HStack(spacing: 12) {
            Text(plugin.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(plugin.enabled ? .primary : .secondary)
            Spacer()
            Group {
                if plugin.enabled {
                    Label(String(localized: "On"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label(String(localized: "Off"), systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .frame(width: 130, alignment: .leading)
        }
    }
}

struct AddTeamMarketplaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let project: String
    let onAdded: () -> Void
    @State private var source = ""
    @State private var running = false
    @State private var output: String?
    @State private var failed = false

    private var trimmed: String { source.trimmingCharacters(in: .whitespaces) }
    private var isValid: Bool { TeamMarketplaces.isValidSource(trimmed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Team Marketplace")
                .font(.headline)
            TextField(String(localized: "owner/repo or git URL"), text: $source)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .disabled(running)
                .onSubmit(add)
            if !trimmed.isEmpty && !isValid {
                Text("Enter a GitHub repository as owner/repo or a git URL.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("Project scope writes the marketplace to .claude/settings.json, which your teammates get through git.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let output {
                ScrollView {
                    Text(output)
                        .font(.caption.monospaced())
                        .foregroundStyle(failed ? .red : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                if running { ProgressView().controlSize(.small) }
                Spacer()
                Button(output != nil && !failed ? String(localized: "Done") : String(localized: "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(running)
                Button(String(localized: "Add"), action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || running)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func add() {
        guard isValid, !running else { return }
        let source = trimmed
        let url = URL(fileURLWithPath: project, isDirectory: true)
        running = true
        output = nil
        Task {
            do {
                let result = try await TeamMarketplaces.add(source: source, project: url)
                output = result.isEmpty ? String(localized: "Marketplace added.") : result
                failed = false
                onAdded()
            } catch {
                output = error.localizedDescription
                failed = true
            }
            running = false
        }
    }
}

extension TeamMarketplace.Origin {
    var title: String {
        switch self {
        case .project: String(localized: "Team")
        case .local: String(localized: "Local")
        case .user: String(localized: "User")
        }
    }

    var explanation: String {
        switch self {
        case .project: String(localized: "Declared in the project's .claude/settings.json and shared through git")
        case .local: String(localized: "Declared in the project's .claude/settings.local.json, only on this Mac")
        case .user: String(localized: "Known to Claude Code for your user account")
        }
    }
}
