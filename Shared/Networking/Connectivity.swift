//
//  Connectivity.swift
//  Gatita
//

import Foundation
import Network
import Observation

/// Whether this device has a network path, watched with NWPathMonitor. The chat shows a banner while it has none,
/// and a message sent then is answered with "Error: No internet access." instead of a request that cannot work.
/// Set GATITA_FORCE_OFFLINE=1 to see the offline screen without unplugging anything.
@Observable
@MainActor
final class Connectivity {
    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let forcedOffline = ProcessInfo.processInfo.environment["GATITA_FORCE_OFFLINE"] == "1"

    init() {
        if forcedOffline {
            isOnline = false
            return
        }
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let online = Connectivity.isOnline(path.status)
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "Gatita.connectivity"))
    }

    deinit {
        monitor.cancel()
    }

    /// A path that works now, or one that comes up on demand (such as a VPN), counts as online.
    nonisolated static func isOnline(_ status: NWPath.Status) -> Bool {
        status != .unsatisfied
    }
}

/// The words and the rule for "no internet". Kept apart from the monitor so they can be tested.
nonisolated enum NoInternet {
    static let headline = "Error: No internet access."
    static let detail = "Gatita needs the internet to answer. Check your Wi-Fi or network connection, then send again."

    /// Network errors that always mean the device is offline.
    private static let offlineCodes: Set<URLError.Code> = [.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff]

    /// Whether an error means there is no internet. Any network error counts while the device has no network path,
    /// except a cancel, which is the user pressing stop.
    static func matches(_ error: Error, online: Bool) -> Bool {
        guard let urlError = error as? URLError, urlError.code != .cancelled else { return false }
        return offlineCodes.contains(urlError.code) || !online
    }

    /// The tool result when a connector could not reach the internet, so the model tells the user instead of retrying.
    static func toolError(service: String) -> String {
        "error: no internet access, so \(service) could not be reached. Tell the user, and do not try again until they say they are back online."
    }
}
