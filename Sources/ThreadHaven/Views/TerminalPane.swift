import SwiftTerm
import SwiftUI
import ThreadHavenCore

struct TerminalHost: NSViewRepresentable {
    let terminal: LocalProcessTerminalView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if terminal.superview !== container { attach(to: container) }
    }

    private func attach(to container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        terminal.removeFromSuperview()
        terminal.frame = container.bounds
        terminal.autoresizingMask = [.width, .height]
        container.addSubview(terminal)
        DispatchQueue.main.async {
            terminal.window?.makeFirstResponder(terminal)
        }
    }
}

struct TerminalPane: View {
    @Environment(SessionStore.self) private var store
    let id: String
    let session: Session?

    var body: some View {
        let terminals = store.terminals
        if let view = terminals.view(for: id) {
            VStack(spacing: 0) {
                TerminalHost(terminal: view)
                    .padding(.leading, 8)
                    .padding(.top, 4)
                    .background(Color(nsColor: .textBackgroundColor))
                if !terminals.isRunning(id) {
                    HStack(spacing: 10) {
                        Label(String(localized: "The session has ended."), systemImage: "stop.circle")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let session {
                            Button(String(localized: "Open Again")) { store.resume(session.id) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .font(.callout)
                    .padding(12)
                    .background(.bar)
                }
            }
        } else if let session, session.isLive {
            PanePlaceholder(
                symbol: "terminal",
                title: String(localized: "Running in another terminal"),
                message: String(localized: "This chat is open in \(session.terminalName). Quit it there to open it here, or jump to it."),
                primary: (String(localized: "Go to Terminal"), { store.focus(session.id) }),
                secondary: nil
            )
        } else if let session {
            PanePlaceholder(
                symbol: "play.rectangle",
                title: String(localized: "Open this chat"),
                message: String(localized: "Resume it right here in ThreadHaven's terminal. Everything works as in a normal terminal, including slash commands."),
                primary: (String(localized: "Open Here"), { store.resume(session.id) }),
                secondary: (String(localized: "Open in \(Preferences.terminal.name)"), {
                    TerminalBridge.openNew(cwd: session.cwd, agent: session.agent, arguments: session.agent.resumeArguments(session.id), terminal: Preferences.terminal)
                })
            )
        }
    }
}

struct PanePlaceholder: View {
    let symbol: String
    let title: String
    let message: String
    let primary: (String, () -> Void)
    let secondary: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            HStack(spacing: 10) {
                Button(primary.0, action: primary.1)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                if let secondary {
                    Button(secondary.0, action: secondary.1).controlSize(.large)
                }
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
