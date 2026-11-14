import AppKit
import ObjectiveC
import SwiftTerm

class ChatTerminalView: LocalProcessTerminalView {
    static let mouseHandling: Void = TerminalMouse.takeOver(ChatTerminalView.self)
}

@MainActor
enum TerminalMouse {
    struct Cell: Equatable {
        let col: Int
        let row: Int
    }

    private static var pendingScroll: [ObjectIdentifier: CGFloat] = [:]

    nonisolated static func takeOver(_ cls: AnyClass) {
        typealias Handler = @convention(c) (AnyObject, Selector, NSEvent) -> Void
        for name in ["mouseMoved:", "mouseDown:", "mouseDragged:", "mouseUp:", "scrollWheel:"] {
            let selector = NSSelectorFromString(name)
            guard let method = class_getInstanceMethod(cls, selector) else { continue }
            let original = unsafeBitCast(method_getImplementation(method), to: Handler.self)
            let replacement: @convention(block) (AnyObject, NSEvent) -> Void = { object, event in
                nonisolated(unsafe) let object = object
                nonisolated(unsafe) let event = event
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let view = object as? LocalProcessTerminalView else { return false }
                    return handle(event, in: view)
                }
                if !handled { original(object, selector, event) }
            }
            class_addMethod(cls, selector, imp_implementationWithBlock(replacement), method_getTypeEncoding(method))
        }
    }

    static func cell(at point: CGPoint, height: CGFloat, cellSize: CGSize, cols: Int, rows: Int) -> Cell {
        guard cellSize.width > 0, cellSize.height > 0, cols > 0, rows > 0 else { return Cell(col: 0, row: 0) }
        let col = Int(max(0, point.x) / cellSize.width)
        let row = Int(max(0, height - point.y) / cellSize.height)
        return Cell(col: min(col, cols - 1), row: min(row, rows - 1))
    }

    static func pixel(at point: CGPoint, height: CGFloat, scale: CGFloat) -> Cell {
        Cell(col: Int(max(0, point.x) * scale), row: Int(max(0, height - point.y) * scale))
    }

    static func wheelLines(delta: CGFloat, precise: Bool, pending: inout CGFloat, cellHeight: CGFloat) -> Int {
        guard delta != 0 else { return 0 }
        guard precise else { return Int(max(1, min(10, abs(delta).rounded()))) * (delta > 0 ? 1 : -1) }
        pending += delta
        let step = max(cellHeight, 1)
        let lines = Int(pending / step)
        pending -= CGFloat(lines) * step
        return max(-10, min(10, lines))
    }

    static func modifierFlags(_ flags: NSEvent.ModifierFlags) -> Int {
        (flags.contains(.shift) ? 4 : 0) + (flags.contains(.control) ? 16 : 0)
    }

    static func handle(_ event: NSEvent, in view: LocalProcessTerminalView) -> Bool {
        let terminal = view.getTerminal()
        let mode = terminal.mouseMode
        guard mode != .off, !event.modifierFlags.contains(.option) else { return false }

        let point = view.convert(event.locationInWindow, from: nil)
        let size = cellSize(of: view, terminal: terminal)
        let cell = cell(at: point, height: view.bounds.height, cellSize: size, cols: terminal.cols, rows: terminal.rows)
        let pixel = pixel(at: point, height: view.bounds.height, scale: view.window?.backingScaleFactor ?? 1)
        let modifiers = modifierFlags(event.modifierFlags)

        func send(_ flags: Int) {
            terminal.sendEvent(buttonFlags: flags, x: cell.col, y: cell.row, pixelX: pixel.col, pixelY: pixel.row)
        }

        switch event.type {
        case .mouseMoved:
            return true
        case .leftMouseDown:
            view.window?.makeFirstResponder(view)
            send(modifiers)
        case .leftMouseDragged:
            if mode == .buttonEventTracking || mode == .anyEvent {
                terminal.sendMotion(buttonFlags: modifiers, x: cell.col, y: cell.row, pixelX: pixel.col, pixelY: pixel.row)
            }
        case .leftMouseUp:
            if mode != .x10 { send(3 + modifiers) }
        case .scrollWheel:
            var pending = pendingScroll[ObjectIdentifier(view)] ?? 0
            let lines = wheelLines(delta: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                                   pending: &pending, cellHeight: size.height)
            pendingScroll[ObjectIdentifier(view)] = pending
            for _ in 0..<abs(lines) { send((lines > 0 ? 64 : 65) + modifiers) }
        default:
            return false
        }
        return true
    }

    private static func cellSize(of view: LocalProcessTerminalView, terminal: Terminal) -> CGSize {
        let frame = view.getOptimalFrameSize()
        let scroller = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        return CGSize(width: (frame.width - scroller) / CGFloat(max(terminal.cols, 1)),
                      height: frame.height / CGFloat(max(terminal.rows, 1)))
    }
}
