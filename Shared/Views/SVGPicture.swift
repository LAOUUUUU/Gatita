//
//  SVGPicture.swift
//  Gatita
//

import CoreGraphics
import Foundation
import SwiftDraw
#if os(macOS)
import AppKit

typealias PlatformImage = NSImage
#else
import UIKit

typealias PlatformImage = UIImage
#endif

/// Draws SVG code blocks as pictures with SwiftDraw, the same on every device (iOS cannot read SVG on its own).
/// Only an SVG that holds everything it draws is drawn: one that names a web address, a file, or a style sheet
/// stays a code block, whose live preview blocks the network. SwiftDraw does not run scripts or animations.
/// Kept apart from the views because SwiftDraw has its own type named `Image`.
nonisolated enum SVGPicture {
    static let maxCharacters = 500_000
    /// The longest side in points; a bigger SVG is drawn smaller, so it can't take up all the memory.
    static let maxSide: CGFloat = 2000
    static let scale: CGFloat = 2

    /// `xmlns` addresses only name the SVG's vocabulary and are never loaded.
    private static let namespace = try! NSRegularExpression(pattern: #"\sxmlns(:[\w-]+)?\s*=\s*("[^"]*"|'[^']*')"#)
    private static let outside = try! NSRegularExpression(
        pattern: #"://|(href|src)\s*=\s*["']\s*//|url\(\s*["']?\s*//|@import|<!ENTITY"#, options: .caseInsensitive)

    /// Whether the SVG names nothing outside itself, such as https://, file://, //host, @import, or an XML entity.
    static func isSelfContained(_ code: String) -> Bool {
        let names = namespace.stringByReplacingMatches(in: code, range: NSRange(code.startIndex..., in: code), withTemplate: " ")
        return outside.firstMatch(in: names, range: NSRange(names.startIndex..., in: names)) == nil
    }

    /// The SVG as a picture, or nil when it is too long, reaches outside itself, or SwiftDraw cannot read it.
    /// Read and drawn off the main thread.
    static func render(_ code: String) async -> PlatformImage? {
        guard code.count <= maxCharacters, isSelfContained(code) else { return nil }
        let drawn = await Task.detached(priority: .userInitiated) { () -> (CGImage, CGSize)? in
            guard let svg = SVG(xml: code) else { return nil }
            return picture(of: svg)
        }.value
        guard let (image, size) = drawn else { return nil }
        #if os(macOS)
        return NSImage(cgImage: image, size: size)
        #else
        return UIImage(cgImage: image, scale: scale, orientation: .up)
        #endif
    }

    /// Draws the SVG on a canvas whose y axis points down, as SVG's does, fitted within `maxSide`.
    static func picture(of svg: SVG) -> (CGImage, CGSize)? {
        guard svg.size.width > 0, svg.size.height > 0 else { return nil }
        let fit = min(1, maxSide / max(svg.size.width, svg.size.height))
        let size = CGSize(width: svg.size.width * fit, height: svg.size.height * fit)
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.draw(svg, in: CGRect(origin: .zero, size: size))
        guard let image = context.makeImage() else { return nil }
        return (image, size)
    }
}
