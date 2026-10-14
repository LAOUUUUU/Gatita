//
//  ScreenSelection.swift
//  Gatita
//

#if os(macOS)
import AppKit

/// Gatita's screenshot picker, like Claude's quick entry: the screens dim, the pointer is a crosshair, and a hint
/// says what to do. Drag over an area, or click a window (it is outlined as the pointer moves over it). Escape, or a
/// click on the quick panel, skips the screenshot. The quick panel stays bright and is never part of the picture.
@MainActor
final class ScreenSelection {
    enum Result {
        /// An area, in global points with the origin at the top left of the main screen.
        case area(CGRect)
        case window(CGWindowID)
        case cancelled
    }

    private var overlays: [SelectionOverlay] = []
    private let panelFrame: () -> CGRect?
    private let onFinish: (Result) -> Void
    private var finished = false

    /// `panelFrame` is the quick panel's frame in AppKit screen coordinates, so it can stay bright and clickable.
    init(panelFrame: @escaping () -> CGRect?, onFinish: @escaping (Result) -> Void) {
        self.panelFrame = panelFrame
        self.onFinish = onFinish
    }

    /// The height of the main screen, which turns AppKit coordinates into top-left ones.
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    func begin() {
        for screen in NSScreen.screens {
            let overlay = SelectionOverlay(screen: screen, selection: self)
            overlays.append(overlay)
            overlay.orderFrontRegardless()
        }
        let mouse = NSEvent.mouseLocation
        (overlays.first { $0.frame.contains(mouse) } ?? overlays.first)?.makeKey()
        NSCursor.crosshair.set()
    }

    func finish(_ result: Result) {
        guard !finished else { return }
        finished = true
        overlays.forEach { $0.orderOut(nil) }
        // The click that ended the selection is still being handled by one of these windows, so they are let go
        // on the next turn of the run loop.
        let closing = overlays
        overlays = []
        DispatchQueue.main.async { _ = closing }
        NSCursor.arrow.set()
        onFinish(result)
    }

    var quickPanelFrame: CGRect? { panelFrame() }

    /// Redraws every screen, since a drag can cross from one to another.
    func redrawAll() {
        overlays.forEach { $0.contentView?.needsDisplay = true }
    }

    // What the overlays share while the pointer moves.
    var dragStart: CGPoint?
    var dragNow: CGPoint?
    /// The window under the pointer, in AppKit coordinates, outlined while nothing is being dragged.
    var hoveredWindow: (id: CGWindowID, frame: CGRect)?

    /// The window under an AppKit point, skipping Gatita's own.
    static func window(at point: CGPoint) -> (id: CGWindowID, frame: CGRect)? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let height = primaryHeight
        guard let found = ScreenGeometry.window(at: ScreenGeometry.topLeft(point, primaryHeight: height), in: list,
                                                excludingPID: Int(ProcessInfo.processInfo.processIdentifier)) else { return nil }
        // The same flip turns the window's top-left bounds back into AppKit coordinates.
        return (found.id, ScreenGeometry.topLeft(found.bounds, primaryHeight: height))
    }
}

/// One screen's dimmed layer. A non-activating panel, so it can take Escape without bringing Gatita forward.
private final class SelectionOverlay: NSPanel {
    weak var selection: ScreenSelection?

    init(screen: NSScreen, selection: ScreenSelection) {
        self.selection = selection
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = SelectionView(selection: selection)
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        selection?.finish(.cancelled)
    }
}

private final class SelectionView: NSView {
    weak var owner: ScreenSelection?
    private var tracking: NSTrackingArea?

    init(selection: ScreenSelection) {
        self.owner = selection
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { owner?.finish(.cancelled) } else { super.keyDown(with: event) }
    }

    override func mouseMoved(with event: NSEvent) {
        guard let selection = owner else { return }
        NSCursor.crosshair.set()
        let point = NSEvent.mouseLocation
        let hovered = selection.quickPanelFrame?.contains(point) == true ? nil : ScreenSelection.window(at: point)
        if hovered?.id != selection.hoveredWindow?.id {
            selection.hoveredWindow = hovered
            selection.redrawAll()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let selection = owner else { return }
        let point = NSEvent.mouseLocation
        // A click on the quick panel skips the screenshot and goes back to typing.
        if selection.quickPanelFrame?.contains(point) == true {
            selection.finish(.cancelled)
            return
        }
        selection.dragStart = point
        selection.dragNow = point
        selection.redrawAll()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let selection = owner else { return }
        NSCursor.crosshair.set()
        selection.dragNow = NSEvent.mouseLocation
        selection.redrawAll()
    }

    override func mouseUp(with event: NSEvent) {
        guard let selection = owner, let start = selection.dragStart else { return }
        let end = NSEvent.mouseLocation
        let height = ScreenSelection.primaryHeight
        if ScreenGeometry.isClick(from: start, to: end) {
            if let window = ScreenSelection.window(at: end) {
                selection.finish(.window(window.id))
            } else {
                selection.finish(.cancelled)
            }
        } else {
            selection.finish(.area(ScreenGeometry.topLeft(ScreenGeometry.rect(from: start, to: end), primaryHeight: height)))
        }
    }

    /// Converts a rect in AppKit screen coordinates into this view's coordinates.
    private func local(_ rect: CGRect) -> CGRect {
        guard let window else { return rect }
        return rect.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let selection = owner else { return }
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        // The quick panel stays bright.
        if let panel = selection.quickPanelFrame, let context = NSGraphicsContext.current {
            context.saveGraphicsState()
            context.compositingOperation = .copy
            NSColor.clear.setFill()
            NSBezierPath(roundedRect: local(panel), xRadius: 22, yRadius: 22).fill()
            context.restoreGraphicsState()
        }

        let accent = NSColor(red: 0.96, green: 0.42, blue: 0.14, alpha: 1)
        if let start = selection.dragStart, let now = selection.dragNow {
            let area = local(ScreenGeometry.rect(from: start, to: now))
            NSColor.clear.setFill()
            area.fill(using: .copy)
            accent.setStroke()
            let outline = NSBezierPath(rect: area.insetBy(dx: -1, dy: -1))
            outline.lineWidth = 2
            outline.stroke()
            let size = "\(Int(area.width)) × \(Int(area.height))"
            drawLabel(size, at: CGPoint(x: area.maxX - 4, y: area.minY - 8), alignRight: true, small: true)
        } else if let hovered = selection.hoveredWindow {
            let frame = local(hovered.frame)
            accent.withAlphaComponent(0.12).setFill()
            frame.fill(using: .sourceOver)
            accent.setStroke()
            let outline = NSBezierPath(roundedRect: frame.insetBy(dx: 1.5, dy: 1.5), xRadius: 10, yRadius: 10)
            outline.lineWidth = 3
            outline.stroke()
        }

        // The hint, on the screen the pointer is on.
        if let window, window.frame.contains(NSEvent.mouseLocation) || selection.dragStart == nil {
            drawLabel("Drag to take a screenshot  ·  Click a window  ·  Esc to skip",
                      at: CGPoint(x: bounds.midX, y: bounds.maxY - 70), alignRight: false, small: false)
        }
    }

    /// A white label on a dark capsule, centered on `point` (or ending at it when `alignRight`).
    private func drawLabel(_ text: String, at point: CGPoint, alignRight: Bool, small: Bool) {
        let font = NSFont.systemFont(ofSize: small ? 11 : 13, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = CGSize(width: small ? 8 : 14, height: small ? 4 : 8)
        let width = size.width + padding.width * 2
        let height = size.height + padding.height * 2
        let x = alignRight ? point.x - width : point.x - width / 2
        let box = CGRect(x: x, y: point.y - height, width: width, height: height)
        NSColor(white: 0.08, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: box, xRadius: height / 2, yRadius: height / 2).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + padding.width, y: box.minY + padding.height), withAttributes: attributes)
    }
}
#endif
