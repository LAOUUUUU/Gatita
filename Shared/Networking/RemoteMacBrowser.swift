//
//  RemoteMacBrowser.swift
//  Gatita
//

import Foundation
import MultipeerConnectivity
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Finds Gatita devices nearby, connects to one with the pairing code, and sends it chats.
/// The device answers with its own key and no project tools.
@MainActor
@Observable
final class RemoteMacBrowser: NSObject {
    /// A nearby device that is running Gatita.
    struct Found: Identifiable {
        let peer: MCPeerID
        var id: String { peer.displayName }
    }

    private(set) var found: [Found] = []
    private(set) var connectedName: String?
    /// What the last connection attempt did, for the Pairing page.
    private(set) var status = ""

    @ObservationIgnored private let peerID: MCPeerID
    @ObservationIgnored private let session: MCSession
    @ObservationIgnored private let browser: MCNearbyServiceBrowser
    @ObservationIgnored private var waiting: CheckedContinuation<String, Error>?
    @ObservationIgnored private var onPiece: ((String) -> Void)?

    override init() {
        #if canImport(UIKit)
        let name = UIDevice.current.name
        #else
        let name = Host.current().name ?? "Gatita"
        #endif
        peerID = MCPeerID(displayName: name)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: "gatita-host")
        super.init()
        session.delegate = self
        browser.delegate = self
        browser.startBrowsingForPeers()
    }

    /// The name this device shows to others. Its own advertiser has the same name, so it is left out of the list.
    var ownName: String {
        peerID.displayName
    }

    /// Invites a nearby device. The pairing code travels with the invitation, and the device accepts only the right code.
    func connect(to device: Found, code: String) {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            status = "Type the pairing code first. It must match the code on your Mac."
            return
        }
        status = "Sent an invitation to \(device.id)."
        browser.invitePeer(device.peer, to: session, withContext: Data(code.utf8), timeout: 30)
    }

    /// Sends one chat to the connected device and waits for its answer. `onPiece` gets each piece as it is written.
    func ask(_ prompt: String, onPiece: @escaping (String) -> Void) async throws -> String {
        guard let peer = session.connectedPeers.first else {
            throw ToolError("Not connected to your Mac. Connect to it in Settings first.")
        }
        guard waiting == nil else {
            throw ToolError("Your Mac is still answering the last message.")
        }
        let data = try JSONEncoder().encode(RemoteMessage.prompt(text: prompt, clientName: peerID.displayName))
        return try await withCheckedThrowingContinuation { continuation in
            waiting = continuation
            self.onPiece = onPiece
            do {
                try session.send(data, toPeers: [peer], with: .reliable)
            } catch {
                finish(with: .failure(error))
            }
        }
    }

    private func finish(with result: Result<String, Error>) {
        let continuation = waiting
        waiting = nil
        onPiece = nil
        switch result {
        case .success(let text):
            continuation?.resume(returning: text)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}

extension RemoteMacBrowser: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connecting:
                self.status = "Connecting to \(peerID.displayName)…"
            case .connected:
                self.connectedName = peerID.displayName
                self.status = "Connected to \(peerID.displayName)."
            case .notConnected:
                if self.connectedName != nil {
                    self.status = "Disconnected from \(self.connectedName ?? "the device")."
                    self.finish(with: .failure(ToolError("Disconnected from your Mac.")))
                } else {
                    self.status = "Could not connect. Check that the pairing code matches, and that pairing is allowed on the other device."
                }
                self.connectedName = nil
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(RemoteMessage.self, from: data) else { return }
        Task { @MainActor in
            switch message {
            case .chunk(let text):
                self.onPiece?(text)
            case .response(let text):
                self.finish(with: .success(text))
            case .prompt, .status:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName: String, fromPeer: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID, with: Progress?) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID, at: URL?, withError: Error?) {}
}

extension RemoteMacBrowser: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peer: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard peer.displayName != self.ownName, !self.found.contains(where: { $0.id == peer.displayName }) else { return }
            self.found.append(Found(peer: peer))
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peer: MCPeerID) {
        Task { @MainActor in
            self.found.removeAll { $0.id == peer.displayName }
        }
    }
}
