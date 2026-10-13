//
//  PromptRail.swift
//  Gatita
//

import Foundation

/// Which prompt the prompt rail highlights.
nonisolated enum PromptRail {
    /// The last prompt that has reached the top of the view. Before any has, the first prompt.
    /// At the bottom of the chat, the last prompt, because it often can't scroll up to the top.
    static func current(order: [UUID], positions: [UUID: CGFloat], offset: CGFloat, atBottom: Bool) -> UUID? {
        if atBottom { return order.last }
        let reached = order.last { (positions[$0] ?? 0) <= offset + 40 }
        return reached ?? order.first
    }
}
