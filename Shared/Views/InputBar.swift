//
//  InputBar.swift
//  Gatita
//
//  Created by LAOUUU on 2026-10-08.
//

import SwiftUI

/// Input bar for client devices (tvOS, visionOS, iOS, macOS when not hosting).
/// Sends prompts to the host device over MultipeerConnectivity instead of
/// calling the Gatita API directly.
struct InputBar: View {
    @Bindable var session: ClientSession
    @State private var input: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 4) {
            if !session.isConnected {
                Label("Searching for host…", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("Ask Gatita…", text: $input)
                    .focused($focused)
                    #if !os(tvOS)
                    .textFieldStyle(.roundedBorder)
                    #endif
                    .onSubmit(send)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                }
                .disabled(!session.isConnected || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        session.sendPrompt(text)
        input = ""
    }
}
