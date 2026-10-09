//
//  HostSession.swift
//  Gatita
//
//  Created by LAOUUU on 2026-10-08.
//


import Foundation
import MultipeerConnectivity
import Observation

#if os(iOS)
import WatchConnectivity
import UIKit
#endif

@Observable
@MainActor
final class HostSession: NSObject {
    var receivedPrompts: [String] = []
    var lastResponse: String = ""
    var connectedClientCount = 0

    private let serviceType = "gatita-host"
    private let peerID: MCPeerID

    nonisolated private let mcSession: MCSession
    nonisolated private let advertiser: MCNearbyServiceAdvertiser

    private let client = GatitaClient(
        apiKey: ProcessInfo.processInfo.environment["GATITA_API_KEY"] ?? "",
        tools: ProjectTools.fromEnvironment())

    override init() {
        #if os(iOS)
        let peerID = MCPeerID(displayName: UIDevice.current.name)
        #else
        let peerID = MCPeerID(displayName: Host.current().name ?? "Gatita Host")
        #endif
        self.peerID = peerID
        self.mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        self.advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        super.init()

        mcSession.delegate = self
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()

        #if os(iOS)
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        #endif
    }

    private func handlePrompt(_ text: String, from source: String) async -> String {
        receivedPrompts.append("[\(source)] \(text)")
        do {
            let reply = try await client.send(messages: [ChatMessage(role: "user", content: text)])
            lastResponse = reply
            return reply
        } catch {
            let message = "Error: \(error.localizedDescription)"
            lastResponse = message
            return message
        }
    }
}

extension HostSession: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in self.connectedClientCount = session.connectedPeers.count }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(RemoteMessage.self, from: data),
              case .prompt(let text, _) = message else { return }
        Task { @MainActor in
            let reply = await self.handlePrompt(text, from: peerID.displayName)
            if let responseData = try? JSONEncoder().encode(RemoteMessage.response(text: reply)) {
                try? session.send(responseData, toPeers: [peerID], with: .reliable)
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName: String, fromPeer: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID, with: Progress?) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID, at: URL?, withError: Error?) {}
}

extension HostSession: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, mcSession)
    }
}

#if os(iOS)
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
            let reply = await self.handlePrompt(text, from: "Watch")
            replyHandler(["response": reply])
        }
    }
}
#endif