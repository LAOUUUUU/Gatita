//
//  GatitaServices.swift
//  Gatita
//

#if os(macOS)
import AppKit

/// "Ask Gatita" in the Services menu of any Mac app (right-click selected text, then Services). The selected text
/// opens the quick panel, attached to the next question. Declared under NSServices in Info.plist; the app must be
/// in /Applications for macOS to list it.
@MainActor
final class GatitaServices: NSObject {
    private let onText: (String) -> Void
    /// The one provider, kept alive for as long as Gatita runs.
    private static var provider: GatitaServices?

    init(onText: @escaping (String) -> Void) {
        self.onText = onText
    }

    /// Makes the service live, and asks macOS to list it now rather than after the next log in.
    static func register(viewModel: ChatViewModel) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let provider = GatitaServices { text in
            QuickPanelController.shared.show(viewModel, selection: text)
        }
        Self.provider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
    }

    /// The handler named by NSMessage in Info.plist. Its selector is askGatita:userData:error:.
    @objc func askGatita(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            error.pointee = "No text was selected, so there is nothing to ask Gatita about."
            return
        }
        onText(text)
    }
}
#endif
