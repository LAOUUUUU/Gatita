//
//  ScreenGeometryTests.swift
//  GatitaTests
//

import CoreGraphics
import XCTest
@testable import Gatita

/// The math behind Gatita's own screenshot selection: the dragged rectangle, a click versus a drag, the flip from
/// AppKit's bottom-left origin to the top-left one the capture uses, and the window under the pointer.
final class ScreenGeometryTests: XCTestCase {
    func testADragInAnyDirectionMakesTheSameRectangle() {
        let expected = CGRect(x: 10, y: 20, width: 90, height: 60)
        XCTAssertEqual(ScreenGeometry.rect(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 100, y: 80)), expected)
        XCTAssertEqual(ScreenGeometry.rect(from: CGPoint(x: 100, y: 80), to: CGPoint(x: 10, y: 20)), expected)
    }

    func testATinyMoveIsAClickNotADrag() {
        XCTAssertTrue(ScreenGeometry.isClick(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 7, y: 6)))
        XCTAssertFalse(ScreenGeometry.isClick(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 30, y: 6)))
    }

    func testAppKitRectsFlipToTopLeftCoordinates() {
        // On a 900-point-tall main screen, a rect 100 points above the bottom edge is 800 - height from the top.
        let flipped = ScreenGeometry.topLeft(CGRect(x: 50, y: 100, width: 200, height: 150), primaryHeight: 900)
        XCTAssertEqual(flipped, CGRect(x: 50, y: 650, width: 200, height: 150))
        let point = ScreenGeometry.topLeft(CGPoint(x: 10, y: 0), primaryHeight: 900)
        XCTAssertEqual(point, CGPoint(x: 10, y: 900))
    }

    func testARectBecomesLocalToItsDisplayAndStaysInside() {
        let display = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(ScreenGeometry.local(CGRect(x: 1500, y: 100, width: 300, height: 200), in: display),
                       CGRect(x: 60, y: 100, width: 300, height: 200))
        XCTAssertEqual(ScreenGeometry.local(CGRect(x: 1400, y: 1000, width: 100, height: 200), in: display),
                       CGRect(x: 0, y: 1000, width: 60, height: 80), "the part off the display is cut")
    }

    private func info(_ id: Int, pid: Int, layer: Int = 0, x: Double, y: Double, w: Double, h: Double) -> [String: Any] {
        ["kCGWindowNumber": id, "kCGWindowOwnerPID": pid, "kCGWindowLayer": layer,
         "kCGWindowBounds": ["X": x, "Y": y, "Width": w, "Height": h]]
    }

    func testTheFrontmostWindowUnderThePointerIsChosen() {
        let windows = [
            info(1, pid: 99, x: 0, y: 0, w: 2000, h: 30),                        // ours: skipped
            info(2, pid: 50, layer: 25, x: 0, y: 0, w: 2000, h: 30),             // the menu bar layer: skipped
            info(3, pid: 60, x: 100, y: 100, w: 500, h: 400),                     // front window
            info(4, pid: 70, x: 0, y: 0, w: 1400, h: 900),                        // behind it
        ]
        XCTAssertEqual(ScreenGeometry.window(at: CGPoint(x: 200, y: 200), in: windows, excludingPID: 99)?.id, 3)
        XCTAssertEqual(ScreenGeometry.window(at: CGPoint(x: 900, y: 600), in: windows, excludingPID: 99)?.id, 4)
        XCTAssertEqual(ScreenGeometry.window(at: CGPoint(x: 200, y: 200), in: windows, excludingPID: 99)?.bounds,
                       CGRect(x: 100, y: 100, width: 500, height: 400))
        XCTAssertNil(ScreenGeometry.window(at: CGPoint(x: 1800, y: 1000), in: windows, excludingPID: 99))
    }
}
