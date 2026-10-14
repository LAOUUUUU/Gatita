//
//  ScreenShot.swift
//  Gatita
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a screenshot into a picture for a message: scaled so its longest side is at most 1,600 pixels (a Retina
/// screen is far bigger), and saved as JPEG, so it stays well under the picture limit.
nonisolated enum ScreenShot {
    static let maxSide = 1600

    /// The size that fits in `maxSide` with the same shape. A picture that already fits keeps its size.
    static func fittedSize(width: Int, height: Int, maxSide: Int = maxSide) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > maxSide, longest > 0 else { return (width, height) }
        let scale = Double(maxSide) / Double(longest)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    /// The picture as a JPEG attachment named "<name>.jpg". Nil when it cannot be drawn or encoded.
    static func attachment(from image: CGImage, name: String) -> ChatImage? {
        let size = fittedSize(width: image.width, height: image.height)
        guard let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let scaled = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return ChatImage(name: name + ".jpg", mimeType: "image/jpeg", data: data as Data)
    }

}
