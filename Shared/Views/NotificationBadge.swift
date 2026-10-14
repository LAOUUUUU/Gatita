//
//  NotificationBadge.swift
//  Gatita
//

import SwiftUI

/// Top-right indicator: an orange question while Gatita is waiting for your answer. A finished reply is a system
/// notification instead (sent while Gatita is not in front), not a badge.
struct NotificationBadge: View {
    @Bindable var viewModel: ChatViewModel
    @State private var showingQuestion = false

    var body: some View {
        if let question = viewModel.pendingQuestion {
            Button {
                showingQuestion = true
            } label: {
                Label("Gatita asks", systemImage: "questionmark.bubble.fill")
                    .foregroundStyle(.orange)
            }
            .popover(isPresented: $showingQuestion) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Gatita asks")
                        .font(.headline)
                    Text(question)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Answer by typing in the box below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Got it") {
                        viewModel.dismissQuestion()
                        showingQuestion = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
                .frame(width: 320)
                .background(Theme.surface)
            }
            .presentationBackground(Theme.surface)
        }
    }
}
