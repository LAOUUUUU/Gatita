//
//  HostSession.swift
//  Gatita
//
//  Created by LAOUUU on 2026-10-08.
//


import Foundation
import MultipeerConnectivity
import Observation

#if os(iOS) || os(visionOS)
import UIKit
#endif

#if os(iOS)
import WatchConnectivity
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
        #if os(macOS)
        let peerID = MCPeerID(displayName: Host.current().name ?? "Gatita Host")
        #else
        let peerID = MCPeerID(displayName: UIDevice.current.name)
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

    /// Sends one message to a client. MCSession can be used from any thread.
    nonisolated static func send(_ message: RemoteMessage, to peer: MCPeerID, through session: MCSession) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: [peer], with: .reliable)
    }

    /// Answers one prompt. `onPiece` gets each piece of the reply as Gatita writes it.
    private func handlePrompt(_ text: String, from source: String, onPiece: (String) -> Void) async -> String {
        receivedPrompts.append("[\(source)] \(text)")
        do {
            let reply = try await client.stream(messages: [ChatMessage(role: "user", content: text)]) { event in
                if case .text(let piece) = event { onPiece(piece) }
            }
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
            let reply = await self.handlePrompt(text, from: peerID.displayName) { piece in
                Self.send(.chunk(text: piece), to: peerID, through: session)
            }
            Self.send(.response(text: reply), to: peerID, through: session)
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
            let reply = await self.handlePrompt(text, from: "Watch") { _ in }
            replyHandler(["response": reply])
        }
    }
}
#endif