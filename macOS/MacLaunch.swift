//
//  MacLaunch.swift
//  Gatita
//

#if os(macOS)
import AppKit

/// What the Mac starts along with the app.
enum MacLaunch {
    /// The quick panel's shortcuts and "Ask Gatita" in the Services menu, which work from launch, even before (or
    /// without) a window. Returns an observer that stops background commands and local MCP servers as Gatita quits,
    /// so none keeps running on its own; the view model keeps it.
    static func start(_ viewModel: ChatViewModel) -> NSObjectProtocol {
        QuickPanelController.shared.start(viewModel: viewModel)
        GatitaServices.register(viewModel: viewModel)
        return NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                      object: nil, queue: .main) { [weak viewModel] _ in
            MainActor.assumeIsolated {
                _ = viewModel?.tasks.stopAll()
                viewModel?.mcp.stopAllNow()
            }
        }
    }
}
#endif
