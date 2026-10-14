//
//  Clipboard.swift
//  Gatita
//

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Puts text on the system clipboard, and reads it back.
enum Clipboard {
    /// The text on the clipboard, or nil when it holds none.
    static func text() -> String? {
        #if os(macOS)
        NSPasteboard.general.string(forType: .string)
        #else
        UIPasteboard.general.string
        #endif
    }

    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
