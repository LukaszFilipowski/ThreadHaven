import Foundation
import Testing
@testable import ThreadHaven
import ThreadHavenCore

struct SidebarLayoutTests {
    private func session(_ id: String, _ cwd: String, _ minutesAgo: Double) -> Session {
        let meta = TranscriptMeta(sessionId: id, path: "/tmp/\(id).jsonl", cwd: cwd, title: id, modified: Date().addingTimeInterval(-minutesAgo * 60), size: 1)
        return Session(id: id, meta: meta, live: nil)
    }

    @Test func favoritesAreListedOnceWithTheirProject() {
        let sessions = [session("a", "/dev/app", 1), session("b", "/dev/app", 5), session("c", "/dev/web", 3)]
        let layout = SidebarLayout(sessions: sessions, favorites: ["b"])
        #expect(layout.favorites.map(\.id) == ["b"])
        #expect(layout.favorites.first?.project == "app")
        #expect(layout.projects.map(\.name) == ["app", "web"])
        #expect(layout.projects.first?.sessions.map(\.id) == ["a"])
        #expect(layout.ordered.map(\.id) == ["b", "a", "c"])
    }
}
