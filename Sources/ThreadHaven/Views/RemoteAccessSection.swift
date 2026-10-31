import AppKit
import SwiftUI

struct RemoteAccessSection: View {
    @Environment(RemoteAccess.self) private var remote
    @AppStorage(Preferences.remoteIdleHours) private var idleHours = 8
    @AppStorage(Preferences.remotePreviews) private var previews = false
    @AppStorage(Preferences.remoteAllowlist) private var allowlist = ""
    @AppStorage(Preferences.remotePushContact) private var pushContact = ""

    var body: some View {
        Section {
            Toggle(String(localized: "Remote access (preview)"), isOn: enabled)
            if let problem = remote.problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            switch remote.phase {
            case .off:
                EmptyView()
            case .starting:
                ProgressView().controlSize(.small)
            case .running(let port):
                running(port: port)
            }
        } header: {
            Text("Remote access")
        } footer: {
            Text("Check chats and send prompts from your phone through your Tailscale network. ThreadHaven listens only on this Mac, and turning remote access off signs out every device.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var enabled: Binding<Bool> {
        Binding(get: { remote.isEnabled }, set: { $0 ? remote.enable() : remote.disable() })
    }

    @ViewBuilder
    private func running(port: UInt16) -> some View {
        LabeledContent(String(localized: "Address")) {
            Text(remote.probe.dnsName.map { "https://\($0)" } ?? "–").textSelection(.enabled)
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Tailscale.serveCommand(port: port))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                CopyButton(text: Tailscale.serveCommand(port: port))
            }
            Text(remote.probe.serve.served
                ? String(localized: "Published in your tailnet with tailscale serve.")
                : String(localized: "Run this command once in a terminal to publish ThreadHaven in your tailnet."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if remote.servingWarning {
            Label(String(localized: "Paired devices cannot reach this Mac: tailscale serve does not forward to this port. Run the command above."), systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if !remote.webAppAvailable {
            Text("The web app is only included in the app bundle built with make app.")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        if let pairing = remote.pairing {
            PairingView(pairing: pairing)
        } else {
            Button(String(localized: "Pair a Device…")) { remote.pairDevice() }
                .disabled(remote.probe.dnsName == nil)
        }

        ForEach(remote.devices) { device in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                    Text(detail(device)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "Revoke")) { remote.revoke(device.id) }
            }
        }

        Picker(String(localized: "Turn off when idle for"), selection: $idleHours) {
            Text("1 hour").tag(1)
            Text("4 hours").tag(4)
            Text("8 hours").tag(8)
            Text("24 hours").tag(24)
        }
        Toggle(String(localized: "Show message text in phone notifications"), isOn: $previews)
        TextField(String(localized: "Allowed Tailscale users"), text: $allowlist, prompt: Text("Only you"))
            .onChange(of: allowlist) { _, value in remote.applyAllowlist(value) }
        if remote.ownLoginMissing {
            Label(String(localized: "ThreadHaven could not read your Tailscale login, so every request is refused. Enter the allowed tailnet users."), systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            Text("Allowed: \(remote.allowedLogins.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        TextField(String(localized: "Contact for push services"), text: $pushContact, prompt: Text(verbatim: RemoteAccess.defaultPushSubject))
        if remote.rejectedRequests > 0 {
            Text("Rejected requests since start: \(remote.rejectedRequests)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func detail(_ device: RemoteDevice) -> String {
        var parts: [String] = []
        if let platform = device.platform { parts.append(platform) }
        if let login = device.login { parts.append(login) }
        if let used = remote.lastUsed[device.id] {
            parts.append(String(localized: "Last used \(used.formatted(.relative(presentation: .named)))"))
        } else {
            parts.append(String(localized: "Not used yet"))
        }
        if device.push != nil { parts.append(String(localized: "Notifications on")) }
        return parts.joined(separator: " · ")
    }
}

private struct PairingView: View {
    @Environment(RemoteAccess.self) private var remote
    let pairing: RemoteAccess.Pairing

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let image = QRCode.image(for: pairing.url) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 160, height: 160)
                    .padding(8)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Scan this code with your phone's camera, then add the page to your home screen to get notifications.")
                Text("The code contains a key for one device. Do not share it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    CopyButton(text: pairing.url, label: String(localized: "Copy Link"))
                    Button(String(localized: "Done")) { remote.endPairing() }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CopyButton: View {
    let text: String
    var label = String(localized: "Copy")

    var body: some View {
        Button(label) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}
