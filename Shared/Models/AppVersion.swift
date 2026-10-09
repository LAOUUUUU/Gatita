//
//  AppVersion.swift
//  Gatita
//

import Foundation

/// The app's version as shown to the user. The number comes from the app bundle (MARKETING_VERSION).
/// The channel says how far along the build is: Gatita is an alpha, so expect rough edges.
enum AppVersion {
    static let channel = "alpha"

    static var number: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    /// For example "0.0.1 alpha (build 1)".
    static var display: String {
        "\(number) \(channel) (build \(build))"
    }
}
