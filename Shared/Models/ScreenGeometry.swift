//
//  ScreenGeometry.swift
//  Gatita
//

import CoreGraphics
import Foundation

/// The math behind Gatita's screenshot selection, kept apart from AppKit so it can be tested.
///
/// AppKit puts the origin at the bottom left of the main screen, with y going up. Core Graphics window lists and
/// ScreenCaptureKit put it at the top left, with y going down. `topLeft` turns the first into the second.
nonisolated enum ScreenGeometry {
    /// A move shorter than this between press and release is a click, which picks the window under the pointer.
    static let clickDistance: CGFloat = 4

    static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    static func isClick(from start: CGPoint, to end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) < clickDistance
    }

    static func topLeft(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func topLeft(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// A global rect as a rect inside one display, both top-left, with the part off the display cut away.
    static func local(_ rect: CGRect, in display: CGRect) -> CGRect {
        let inside = rect.intersection(display)
        guard !inside.isNull else { return .zero }
        return inside.offsetBy(dx: -display.minX, dy: -display.minY)
    }

    /// The frontmost normal window under a top-left point, from a CGWindowListCopyWindowInfo list (which is in
    /// front-to-back order). Windows of `excludingPID` (Gatita) and anything above the normal layer, such as the
    /// menu bar and the Dock, are skipped.
    static func window(at point: CGPoint, in windows: [[String: Any]], excludingPID: Int) -> (id: UInt32, bounds: CGRect)? {
        for window in windows {
            guard (window["kCGWindowLayer"] as? Int) == 0,
                  (window["kCGWindowOwnerPID"] as? Int) != excludingPID,
                  let id = window["kCGWindowNumber"] as? Int,
                  let box = window["kCGWindowBounds"] as? [String: Any],
                  let x = (box["X"] as? NSNumber)?.doubleValue, let y = (box["Y"] as? NSNumber)?.doubleValue,
                  let width = (box["Width"] as? NSNumber)?.doubleValue, let height = (box["Height"] as? NSNumber)?.doubleValue,
                  width > 40, height > 40 else { continue }
            let bounds = CGRect(x: x, y: y, width: width, height: height)
            if bounds.contains(point) { return (UInt32(id), bounds) }
        }
        return nil
    }
}
