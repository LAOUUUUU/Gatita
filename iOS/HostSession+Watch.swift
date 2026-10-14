//
//  HostSession+Watch.swift
//  Gatita
//

#if os(iOS)
import Foundation
import WatchConnectivity

/// Prompts from the Apple Watch app, which reaches the iPhone through WatchConnectivity and gets the whole answer back.
extension HostSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let text = message["prompt"] as? String else { return }
        Task { @MainActor in
            let reply = await self.handlePrompt(text, from: "Watch") { _ in }
            replyHandler(["response": reply])
        }
    }
}
#endif
