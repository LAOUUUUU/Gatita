//
//  CommandDoubleTap.swift
//  Gatita
//

#if os(macOS)
import AppKit
import CoreGraphics

/// Watches for ⌘ pressed twice, in any app, with a listen-only event tap. It needs Input Monitoring permission
/// (System Settings, Privacy & Security, Input Monitoring), which works in the App Sandbox. It never changes or
/// blocks a key; it only reads the modifier keys and whether a key was typed.
@MainActor
final class CommandDoubleTap {
    enum Status: Equatable {
        case off
        case running
        /// Input Monitoring is not allowed yet, so the tap could not start.
        case needsPermission
    }

    private(set) var status: Status = .off
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var detector = DoubleTapDetector()
    private let action: () -> Void
    private var activationObserver: NSObjectProtocol?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    /// Starts watching. With `ask`, macOS is asked for permission when it is missing. Without permission it tries
    /// again each time Gatita becomes active, so it starts on its own after the switch is turned on in System Settings.
    func start(ask: Bool = false) {
        guard tap == nil else { return }
        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if self?.status == .needsPermission { self?.start() }
                }
            }
        }
        if ask, !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: CGEventMask(mask), callback: { _, type, event, refcon in
            if let refcon {
                let watcher = Unmanaged<CommandDoubleTap>.fromOpaque(refcon).takeUnretainedValue()
                // The tap's source is on the main run loop, so this runs on the main thread.
                MainActor.assumeIsolated { watcher.handle(type, event) }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: me) else {
            status = .needsPermission
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        status = .running
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        detector = DoubleTapDetector()
        status = .off
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system turns a slow tap off; turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            detector.keyDown()
        case .flagsChanged:
            let flags = event.flags
            let others: CGEventFlags = [.maskShift, .maskControl, .maskAlternate]
            if detector.flagsChanged(commandDown: flags.contains(.maskCommand),
                                     otherModifiersDown: !flags.intersection(others).isEmpty,
                                     at: ProcessInfo.processInfo.systemUptime) {
                action()
            }
        default:
            break
        }
    }

    /// Opens System Settings at Input Monitoring, after asking macOS to list Gatita there.
    static func openPrivacySettings() {
        _ = CGRequestListenEventAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
#endif
