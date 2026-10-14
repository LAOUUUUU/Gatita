//
//  DoubleTap.swift
//  Gatita
//

import Foundation

/// Tells two quick taps of ⌘ on its own from everything else, so pressing ⌘ twice can open the quick panel while
/// ⌘C, ⌘⇧ shortcuts, and holding ⌘ never do. It only reads what it is fed; the Mac's event tap feeds it.
nonisolated struct DoubleTapDetector: Sendable {
    /// The most time between the end of the first tap and the end of the second.
    static let window: TimeInterval = 0.45
    /// A press held longer than this is not a tap.
    static let maxHold: TimeInterval = 0.35

    private var pressedAt: TimeInterval?
    private var lastTapAt: TimeInterval?
    /// Another key or modifier joined the press, so it is not a tap.
    private var spoiled = false

    /// A change of the modifier keys. True when it finished a double tap of ⌘.
    mutating func flagsChanged(commandDown: Bool, otherModifiersDown: Bool, at time: TimeInterval) -> Bool {
        if otherModifiersDown {
            spoiled = true
            lastTapAt = nil
            if !commandDown { pressedAt = nil }
            return false
        }
        if commandDown {
            if pressedAt == nil {
                pressedAt = time
                spoiled = false
            }
            return false
        }
        // ⌘ came up.
        guard let pressed = pressedAt else { return false }
        pressedAt = nil
        guard !spoiled, time - pressed <= Self.maxHold else {
            lastTapAt = nil
            return false
        }
        if let last = lastTapAt, time - last <= Self.window {
            lastTapAt = nil
            return true
        }
        lastTapAt = time
        return false
    }

    /// Any key typed. While ⌘ is down this makes a shortcut, not a tap; either way it ends a double tap.
    mutating func keyDown() {
        if pressedAt != nil { spoiled = true }
        lastTapAt = nil
    }
}
