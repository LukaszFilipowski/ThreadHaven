import AppKit
import SwiftUI
import Testing
@testable import ThreadHaven

@MainActor
struct SnapshotHarness {
    @Test func render() async throws {
        guard let out = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        let store = SessionStore()
        try await Task.sleep(for: .seconds(8))
        func shoot<V: View>(_ view: V, _ name: String, _ size: CGSize) async throws {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: view.environment(store).frame(width: size.width, height: size.height))
            window.layoutIfNeeded()
            try await Task.sleep(for: .seconds(3))
            let view = window.contentView!
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
        }
        let live = store.sessions.first(where: \.isLive) ?? store.sessions.first
        store.selection = Set([live?.id].compactMap { $0 })
        try await shoot(ContentView(), "content.png", CGSize(width: 1400, height: 880))
        if let live {
            try await shoot(SessionDetail(session: live), "detail.png", CGSize(width: 960, height: 880))
        }
        let recent = store.sessions.filter { !$0.isLive }.prefix(3).map(\.id)
        try await shoot(PaneGrid(ids: Array(recent)), "panes.png", CGSize(width: 1100, height: 600))
        try await shoot(ChatSidebar(selection: .constant(Set([live?.id].compactMap { $0 })), sessions: store.sessions), "sidebar.png", CGSize(width: 360, height: 880))
    }
}
