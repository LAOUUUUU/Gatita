//
//  QuickPanelSettingsView.swift
//  Gatita
//

import SwiftUI

#if os(macOS)
/// How the quick panel opens: ⌘ pressed twice (which needs Input Monitoring permission) and ⌃⌘G.
struct QuickPanelSettingsView: View {
    @Bindable var viewModel: ChatViewModel
    private var controller: QuickPanelController { .shared }

    var body: some View {
        List {
            Section {
                Toggle("Press ⌘ twice to open the quick panel", isOn: $viewModel.doubleCommandOpensPanel)
                if viewModel.doubleCommandOpensPanel {
                    switch controller.doubleTapStatus {
                    case .running:
                        Label("On. Press ⌘ twice, quickly, in any app.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .needsPermission:
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Gatita needs Input Monitoring permission to notice ⌘ in other apps. Turn Gatita on in the list, then come back here.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            HStack(spacing: 8) {
                                Button("Open Input Monitoring") { CommandDoubleTap.openPrivacySettings() }
                                    .buttonStyle(GatitaButtonStyle(.primary))
                                Button("Check again") { controller.refreshStatus() }
                                    .buttonStyle(GatitaButtonStyle(.secondary))
                            }
                        }
                    case .off:
                        Text("Starting…")
                            .foregroundStyle(.secondary)
                    }
                }
                SettingsNote(Text("⌃⌘G and Chat, then Quick Panel, always open it too. Gatita only reads whether ⌘ was pressed on its own; it never records what you type."))
            }

            Section {
                Toggle("⌘⌘ starts with a screenshot", isOn: $viewModel.doubleCommandTakesScreenshot)
                if ScreenCapture.isAllowed {
                    Label("Screen Recording is allowed.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Screenshots need Screen Recording permission. Turn Gatita on in the list.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Open Screen Recording") {
                            ScreenCapture.requestPermission()
                            ScreenCapture.openPrivacySettings()
                        }
                        .buttonStyle(GatitaButtonStyle(.primary))
                    }
                }
                SettingsNote(Text("Like Claude's quick entry: ⌘⌘ opens the panel and dims the screens. Drag over an area, or click a window, and the screenshot is attached to the panel, which is left out of the picture. Escape, or a click on the panel, skips it. The camera button takes one any time. Nothing is sent until you press Return."))
            } header: {
                Text("Screenshots")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Quick panel")
        .onAppear { controller.refreshStatus() }
    }
}
#endif
