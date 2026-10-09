//
//  SleepGuard.swift
//  Gatita
//

#if os(macOS)
import Foundation

/// Stops the Mac from sleeping on its own while it is on. A person can still put the Mac to sleep,
/// and closing the lid can still sleep it.
@MainActor
final class SleepGuard {
    private var activity: NSObjectProtocol?

    func set(_ on: Bool) {
        if on, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .idleSystemSleepDisabled,
                                                             reason: "Gatita is keeping the Mac awake")
        } else if !on, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }
}
#endif
