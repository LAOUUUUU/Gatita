//
//  ClientSession.swift
//  Gatita
//
//  Created by LAOUUU on 2026-10-08.
//

import Foundation
import MultipeerConnectivity
import Observation

#if canImport(UIKit)
import UIKit
#endif

@Observable
@MainActor
final class ClientSession: NSObject {
    var isConnected = false
    /// The reply so far. It grows while the host streams Gatita's answer.
    var lastResponse = ""
    private var assembler = ReplyAssembler()

    private let serviceType = "gatita-host"
    private let peerID: MCPeerID

    // nonisolated so delegate callbacks (which arrive off the main actor)
    // can touch these without actor-isolation errors. MCSession and
    // MCNearbyServiceBrowser are safe to message from any thread.
    nonisolated private let session: MCSession
    nonisolated private let browser: MCNearbyServiceBrowser

    override init() {
        #if canImport(UIKit)
        let peerID = MCPeerID(displayName: UIDevice.current.name)
        #else
        let peerID = MCPeerID(displayName: Host.current().name ?? "Gatita Client")
        #endif
        self.peerID = peerID
        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        self.browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        super.init()
        session.delegate = self
        browser.delegate = self
        browser.startBrowsingForPeers()
    }

    func sendPrompt(_ text: String) {
        assembler = ReplyAssembler()
        lastResponse = ""
        guard let data = try? JSONEncoder().encode(RemoteMessage.prompt(text: text, clientName: peerID.displayName)),
              !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
}

extension ClientSession: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in self.isConnected = state == .connected }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(RemoteMessage.self, from: data) else { return }
        Task { @MainActor in
            self.assembler.receive(message)
            self.lastResponse = self.assembler.text
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName: String, fromPeer: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID, with: Progress?) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID, at: URL?, withError: Error?) {}
}

extension ClientSession: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
