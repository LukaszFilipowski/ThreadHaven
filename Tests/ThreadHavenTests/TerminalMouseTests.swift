import AppKit
import CoreGraphics
import SwiftTerm
import Foundation
import Testing
@testable import ThreadHaven
import ThreadHavenCore

struct TerminalMouseTests {
    private let size = CGSize(width: 8, height: 16)

    @Test @MainActor func cellIsCountedFromTheTopOfTheVisibleScreen() {
        let top = TerminalMouse.cell(at: CGPoint(x: 1, y: 399), height: 400, cellSize: size, cols: 80, rows: 25)
        #expect(top == TerminalMouse.Cell(col: 0, row: 0))
        let inside = TerminalMouse.cell(at: CGPoint(x: 20, y: 400 - 33), height: 400, cellSize: size, cols: 80, rows: 25)
        #expect(inside == TerminalMouse.Cell(col: 2, row: 2))
        let outside = TerminalMouse.cell(at: CGPoint(x: 9_999, y: -50), height: 400, cellSize: size, cols: 80, rows: 25)
        #expect(outside == TerminalMouse.Cell(col: 79, row: 24))
    }

    @Test @MainActor func pixelPositionsUseScreenPixelsLikeTheReportedCellSize() {
        let pixel = TerminalMouse.pixel(at: CGPoint(x: 10, y: 380), height: 400, scale: 2)
        #expect(pixel == TerminalMouse.Cell(col: 20, row: 40))
    }

    @Test @MainActor func trackpadScrollingIsTurnedIntoWholeLines() {
        var pending: CGFloat = 0
        #expect(TerminalMouse.wheelLines(delta: 10, precise: true, pending: &pending, cellHeight: 16) == 0)
        #expect(TerminalMouse.wheelLines(delta: 10, precise: true, pending: &pending, cellHeight: 16) == 1)
        #expect(pending == 4)
        #expect(TerminalMouse.wheelLines(delta: -40, precise: true, pending: &pending, cellHeight: 16) == -2)
    }

    @Test @MainActor func mouseWheelScrollsAtLeastOneLine() {
        var pending: CGFloat = 0
        #expect(TerminalMouse.wheelLines(delta: 0.2, precise: false, pending: &pending, cellHeight: 16) == 1)
        #expect(TerminalMouse.wheelLines(delta: -3, precise: false, pending: &pending, cellHeight: 16) == -3)
        #expect(TerminalMouse.wheelLines(delta: 0, precise: false, pending: &pending, cellHeight: 16) == 0)
    }

    @Test func customTitleWinsOverTheTranscriptTitle() {
        let meta = TranscriptMeta(sessionId: "a", path: "/tmp/a.jsonl", cwd: "/dev/app", title: "From Claude", modified: Date(), size: 1)
        var session = Session(id: "a", meta: meta, live: nil)
        #expect(session.title == "From Claude")
        session.customTitle = "Mine"
        #expect(session.title == "Mine")
    }
}

@MainActor
final class CapturingTerminalView: ChatTerminalView {
    var sent = ""

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        sent += String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\u{1b}", with: "^")
    }
}

@MainActor
struct TerminalMouseDispatchTests {
    private func makeView() -> (CapturingTerminalView, NSWindow) {
        _ = ChatTerminalView.mouseHandling
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        let view = CapturingTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        window.contentView = view
        view.getTerminal().feed(text: "\u{1b}[?1003h\u{1b}[?1006h")
        view.sent = ""
        return (view, window)
    }

    private func event(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    @Test func hoverIsNotSentAndAClickIsSentOnce() {
        let (view, window) = makeView()
        let point = NSPoint(x: 20, y: 500 - 40)
        view.perform(NSSelectorFromString("mouseMoved:"), with: event(.mouseMoved, at: point, in: window))
        #expect(view.sent.isEmpty)
        view.perform(NSSelectorFromString("mouseDown:"), with: event(.leftMouseDown, at: point, in: window))
        view.perform(NSSelectorFromString("mouseUp:"), with: event(.leftMouseUp, at: point, in: window))
        let cell = TerminalMouse.cell(at: point, height: view.bounds.height,
                                      cellSize: CGSize(width: (view.getOptimalFrameSize().width - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)) / CGFloat(view.getTerminal().cols),
                                                       height: view.getOptimalFrameSize().height / CGFloat(view.getTerminal().rows)),
                                      cols: view.getTerminal().cols, rows: view.getTerminal().rows)
        #expect(view.sent == "^[<0;\(cell.col + 1);\(cell.row + 1)M^[<0;\(cell.col + 1);\(cell.row + 1)m")
        #expect(cell.row == 2)
        _ = window
    }

    @Test func mouseWheelGoesToTheAppAsWheelEvents() throws {
        let (view, _) = makeView()
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 2, wheel2: 0, wheel3: 0))
        let wheel = try #require(NSEvent(cgEvent: cg))
        view.perform(NSSelectorFromString("scrollWheel:"), with: wheel)
        #expect(view.sent.contains("^[<64;"))
        #expect(!view.sent.contains("^[<65;"))
    }

    @Test func withoutMouseTrackingTheTerminalKeepsItsOwnHandling() {
        let (view, window) = makeView()
        view.getTerminal().feed(text: "\u{1b}[?1003l\u{1b}[?1006l")
        view.perform(NSSelectorFromString("mouseMoved:"), with: event(.mouseMoved, at: NSPoint(x: 20, y: 400), in: window))
        #expect(view.sent.isEmpty)
    }
}
