//
//  ModeSwitch.swift
//  Gatita
//

#if os(macOS)
import SwiftUI

/// Chat and Code as two icons in a black pill, at the top of the sidebar, like Claude's switch. The selected icon is orange.
struct ModeSwitch: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        HStack(spacing: 2) {
            modeButton(.chat, icon: "bubble.left")
            modeButton(.code, icon: "chevron.left.forwardslash.chevron.right")
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08)))
        .fixedSize()
    }

    private func modeButton(_ mode: GatitaMode, icon: String) -> some View {
        let selected = viewModel.mode == mode
        return Button {
            viewModel.switchMode(to: mode)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? Theme.accent : Color.secondary)
                .frame(width: 34, height: 24)
                .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.white.opacity(0.08) : Color.clear))
        }
        .buttonStyle(.plain)
        .help("\(mode.displayName): \(mode.summary)")
        .accessibilityLabel(mode.displayName)
    }
}
#endif
