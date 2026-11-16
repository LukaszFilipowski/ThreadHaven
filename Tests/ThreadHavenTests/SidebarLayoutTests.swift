import Foundation
import Testing
@testable import ThreadHaven
import ThreadHavenCore

struct SidebarLayoutTests {
    private func session(_ id: String, _ cwd: String, _ minutesAgo: Double) -> Session {
        let meta = TranscriptMeta(sessionId: id, path: "/tmp/\(id).jsonl", cwd: cwd, title: id, modified: Date().addingTimeInterval(-minutesAgo * 60), size: 1)
        return Session(id: id, meta: meta, live: nil)
    }

    @Test func favoritesAreListedOnceAndRecentIsFlat() {
        let sessions = [session("a", "/dev/app", 1), session("b", "/dev/app", 5), session("c", "/dev/web", 3)]
        let layout = SidebarLayout(sessions: sessions, favorites: ["b"])
        #expect(layout.favorites.map(\.id) == ["b"])
        #expect(layout.favorites.first?.project == "app")
        #expect(layout.recent.map(\.id) == ["a", "c"])
        #expect(layout.ordered.map(\.id) == ["b", "a", "c"])
    }

    @Test func recentIsLimitedToTheNewestChats() {
        let sessions = (0..<5).map { session("s\($0)", "/dev/p\($0 % 2)", Double($0)) }
        let layout = SidebarLayout(sessions: sessions, limit: 3)
        #expect(layout.recent.map(\.id) == ["s0", "s1", "s2"])
        #expect(layout.hidden == 2)
    }

    @Test func recentSearchMatchesFolderAndDescriptionWithoutLimit() {
        var sessions = (0..<40).map { session("s\($0)", "/dev/other", Double($0)) }
        sessions.append(session("Żółw migracja bazy", "/Users/me/projects/cosmic-web", 100))
        sessions.append(session("deploy", "/Users/me/projects/threadhaven", 200))
        let byFolder = SidebarLayout(sessions: sessions, limit: 30, recentQuery: "Cosmic")
        #expect(byFolder.recent.map(\.id) == ["Żółw migracja bazy"])
        #expect(byFolder.hidden == 0)
        #expect(byFolder.recentTotal == 42)
        #expect(SidebarLayout(sessions: sessions, limit: 30, recentQuery: "zolw BAZY").recent.count == 1)
        #expect(SidebarLayout(sessions: sessions, limit: 30, recentQuery: "threadhaven deploy").recent.map(\.id) == ["deploy"])
        let none = SidebarLayout(sessions: sessions, limit: 30, recentQuery: "nothing-like-this")
        #expect(none.recent.isEmpty && none.recentTotal == 42)
        #expect(SidebarLayout(sessions: sessions, limit: 30, recentQuery: "  ").recent.count == 30)
    }

    @Test func paneOrderKeepsExistingPanesInPlace() {
        let order = PaneGrid.order(["b", "a"], selection: ["a", "b", "c"], pending: [])
        #expect(order == ["b", "a", "c"])
        #expect(PaneGrid.order(order, selection: ["a", "c"], pending: []) == ["a", "c"])
    }

    @Test func paneGridColumns() {
        #expect((1...6).map(PaneGrid.columns) == [1, 2, 3, 2, 3, 3])
    }

    @Test func layoutKeepsShownChatsAndFillsWithRunningOnes() {
        #expect(PaneGrid.panes(count: 3, keeping: ["b"], running: ["a", "b", "c", "d"]) == ["b", "a", "c"])
        #expect(PaneGrid.panes(count: 1, keeping: ["b", "a"], running: ["a"]) == ["b"])
        #expect(PaneGrid.panes(count: 6, keeping: [], running: ["a", "b"]) == ["a", "b"])
    }

    @Test func resumeCommandStartsInTheChatFolder() {
        let meta = TranscriptMeta(sessionId: "abc", path: "/tmp/abc.jsonl", cwd: "/Users/me/my app", title: "t", modified: Date(), size: 1)
        let session = Session(id: "abc", meta: meta, live: nil)
        #expect(session.resumeCommand == "cd '/Users/me/my app' && claude '--resume' 'abc'")
    }
}
