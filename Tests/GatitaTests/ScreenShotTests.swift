//
//  ScreenShotTests.swift
//  GatitaTests
//

import CoreGraphics
import ImageIO
import XCTest
@testable import Gatita

/// Screenshots for the quick panel: big Retina captures are made smaller before they are sent.
final class ScreenShotTests: XCTestCase {
    func testABigScreenshotIsScaledDownKeepingItsShape() {
        XCTAssertEqual(ScreenShot.fittedSize(width: 5120, height: 2880, maxSide: 1600).width, 1600)
        XCTAssertEqual(ScreenShot.fittedSize(width: 5120, height: 2880, maxSide: 1600).height, 900)
        XCTAssertEqual(ScreenShot.fittedSize(width: 1000, height: 3000, maxSide: 1600).height, 1600)
        XCTAssertEqual(ScreenShot.fittedSize(width: 1000, height: 3000, maxSide: 1600).width, 533)
    }

    func testASmallScreenshotKeepsItsSize() {
        let size = ScreenShot.fittedSize(width: 800, height: 600, maxSide: 1600)
        XCTAssertEqual(size.width, 800)
        XCTAssertEqual(size.height, 600)
    }

    func testAScreenshotBecomesAJPEGAttachment() throws {
        let image = try XCTUnwrap(Self.image(width: 3200, height: 2000))
        let attachment = try XCTUnwrap(ScreenShot.attachment(from: image, name: "Screenshot"))
        XCTAssertEqual(attachment.mimeType, "image/jpeg")
        XCTAssertEqual(attachment.name, "Screenshot.jpg")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(attachment.data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 1600)
        XCTAssertEqual(decoded.height, 1000)
        XCTAssertLessThan(attachment.data.count, 4_000_000, "under the picture limit for one message")
    }

    func testScreenshotFirstIsOnByDefaultAndSaved() throws {
        XCTAssertTrue(AppSettings().doubleCommandTakesScreenshot)
        let data = try JSONEncoder().encode(AppSettings(doubleCommandTakesScreenshot: false))
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: data).doubleCommandTakesScreenshot)
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).doubleCommandTakesScreenshot)
    }

    /// A plain test image with a gradient, so the JPEG is not trivially small.
    private static func image(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for x in stride(from: 0, to: width, by: 40) {
            context.setFillColor(red: CGFloat(x) / CGFloat(width), green: 0.4, blue: 0.2, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 40, height: height))
        }
        return context.makeImage()
    }
}
