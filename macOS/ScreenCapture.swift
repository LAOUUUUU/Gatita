//
//  ScreenCapture.swift
//  Gatita
//

#if os(macOS)
import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Takes the quick panel's screenshots with ScreenCaptureKit: an area of the screen with all of Gatita's windows
/// (the quick panel and the main window) left out, so only what is behind them shows, or one window.
/// It needs Screen Recording permission.
enum ScreenCapture {
    /// What to capture. An area is in global points with the origin at the top left of the main screen.
    enum Target: Sendable {
        case area(CGRect)
        case window(CGWindowID)
    }

    /// Whether Screen Recording is allowed. Never asks.
    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks macOS for Screen Recording permission. The answer arrives later, in System Settings.
    static func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    /// Opens System Settings at Screen Recording.
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The screenshot as an attachment, or nil when the area or window is gone or capturing failed.
    @concurrent
    static func capture(_ target: Target) async -> ChatImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let filter: SCContentFilter
            let configuration = SCStreamConfiguration()
            configuration.showsCursor = false
            switch target {
            case .area(let rect):
                guard let display = content.displays.first(where: { $0.frame.intersects(rect) }) else { return nil }
                let gatita = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                filter = SCContentFilter(display: display, excludingApplications: gatita, exceptingWindows: [])
                let local = ScreenGeometry.local(rect, in: display.frame)
                guard local.width >= 2, local.height >= 2 else { return nil }
                configuration.sourceRect = local
                configuration.width = Int(local.width * CGFloat(filter.pointPixelScale))
                configuration.height = Int(local.height * CGFloat(filter.pointPixelScale))
            case .window(let id):
                guard let window = content.windows.first(where: { $0.windowID == id }) else { return nil }
                filter = SCContentFilter(desktopIndependentWindow: window)
                configuration.ignoreShadowsSingleWindow = true
                configuration.width = Int(window.frame.width * CGFloat(filter.pointPixelScale))
                configuration.height = Int(window.frame.height * CGFloat(filter.pointPixelScale))
            }
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let stamp = Date().formatted(.dateTime.hour().minute().second())
            return ScreenShot.attachment(from: image, name: "Screenshot \(stamp)")
        } catch {
            return nil
        }
    }
}
#endif
