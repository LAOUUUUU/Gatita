//
//  ImageThumbnail.swift
//  Gatita
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A picture from its data, cropped to a square. Clip it to a shape at the call site.
struct ImageThumbnail: View {
    let data: Data
    let side: CGFloat

    var body: some View {
        #if os(macOS)
        Image(nsImage: NSImage(data: data) ?? NSImage())
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .clipped()
        #else
        Image(uiImage: UIImage(data: data) ?? UIImage())
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .clipped()
        #endif
    }
}
