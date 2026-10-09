//
//  ChatView.swift
//  Gatita
//
//  Created by LAOUUU on 2026-10-08.
//


import SwiftUI

struct ChatView: View {
    let viewModel: ChatViewModel
    let clientSession: ClientSession?
    @State private var showFiles = true
    @State private var showPullRequest = false

    /// Changes whenever the newest reply grows, so the view keeps following the stream.
    private var scrollToken: String {
        guard let last = viewModel.messages.last else { return "" }
        return "\(viewModel.messages.count)-\(last.content.count)-\(last.reasoning.count)-\(last.activities.count)"
    }

    var body: some View {
        HStack(spacing: 0) {
            #if os(macOS)
            if clientSession == nil && showFiles {
                ProjectFilesView(tools: viewModel.projectTools)
                Divider()
            }
            #endif

            VStack(spacing: 0) {
                #if !os(watchOS)
                if clientSession == nil {
                    header
                }
                #endif

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: scrollToken) { _, _ in
                        if let last = viewModel.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                if clientSession == nil, viewModel.projectRoot.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("No project folder set, so Gatita has no file tools. Open Settings and enter it.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                #if os(watchOS)
                WatchInputBar(viewModel: viewModel)
                #else
                if let clientSession {
                    InputBar(session: clientSession)
                } else {
                    HostInputBar(viewModel: viewModel)
                }
                #endif
            }
        }
        #if os(visionOS)
        .glassBackgroundEffect()
        #endif
        #if os(macOS)
        .sheet(isPresented: $showPullRequest) {
            pullRequestSheet
        }
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var pullRequestSheet: some View {
        if let root = viewModel.projectTools?.root {
            PullRequestView(folder: root, analytics: viewModel.analytics, log: viewModel.log,
                            draft: { prompt in try await viewModel.oneShot(prompt) })
        } else {
            Text("Set a project folder in Settings first.")
                .padding()
        }
    }
    #endif

    #if !os(watchOS)
    private var header: some View {
        HStack(spacing: 14) {
            #if os(macOS)
            Button {
                showFiles.toggle()
            } label: {
                Label("Files", systemImage: "sidebar.left")
            }
            Button {
                showPullRequest = true
            } label: {
                Label("Create PR", systemImage: "arrow.triangle.pull")
            }
            #endif
            Spacer()
            Button {
                viewModel.clear()
            } label: {
                Label("New chat", systemImage: "square.and.pencil")
            }
            .disabled(viewModel.messages.isEmpty)
        }
        .buttonStyle(.plain)
        .font(.callout.weight(.medium))
        .padding(.horizontal)
        .padding(.top, 6)
    }
    #endif
}
