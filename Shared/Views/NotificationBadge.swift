//
//  NotificationBadge.swift
//  Gatita
//

import SwiftUI

/// Top-right indicator: a green check when a reply has finished, or an orange question when Gatita is waiting for you.
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
        } else if viewModel.finishedReplies > 0 {
            Button {
                viewModel.acknowledgeFinished()
            } label: {
                Label("Finished (\(viewModel.finishedReplies))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .help("Gatita finished a reply. Click to clear.")
        }
    }
}
