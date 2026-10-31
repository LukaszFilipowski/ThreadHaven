import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class QuickSwitcher {
    private let store: SessionStore
    private var hotKey: HotKey?
    private var panel: NSPanel?
    private var observer: NSObjectProtocol?

    init(store: SessionStore) {
        self.store = store
        applyPreference()
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPreference() }
        }
    }

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    private func applyPreference() {
        let enabled = UserDefaults.standard.bool(forKey: Preferences.quickSwitcher)
        guard enabled != (hotKey != nil) else { return }
        hotKey = enabled
            ? HotKey(keyCode: kVK_Space, modifiers: controlKey | optionKey) { [weak self] in
                MainActor.assumeIsolated { self?.toggle() }
            }
            : nil
    }

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(
            rootView: QuickSwitcherView(onPick: { [weak self] id in self?.pick(id) }, onClose: { [weak self] in self?.close() })
                .environment(store)
        )
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() {
        panel?.orderOut(nil)
    }

    private func pick(_ id: String) {
        close()
        guard let session = store.session(id) else { return }
        if session.isLive { store.focus(id) } else { store.resume(id) }
    }

    private func makePanel() -> NSPanel {
        let panel = SwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        return panel
    }
}

private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
