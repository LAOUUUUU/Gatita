//
//  Support.swift
//  GatitaTests
//

import Darwin
import Foundation
import XCTest
@testable import Gatita

/// Paths inside this repository, found from this file's location.
enum RepoPaths {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // GatitaTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // the repository
    static let mockServer = root.appendingPathComponent("Tests/MockServer/mock_server.py")
    static let plugins = root.appendingPathComponent("Tests/Fixtures/plugins")
}

/// A new empty folder. It is removed when the test ends.
func temporaryFolder(_ test: XCTestCase, name: String = "gatita-tests") -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    test.addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    return folder
}

/// A throwaway project with one source file and a .git folder. It is removed when the test ends.
func makeProjectFixture(_ test: XCTestCase) throws -> URL {
    let root = temporaryFolder(test, name: "gatita-project")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("App"), withIntermediateDirectories: true)
    try "let app = 1\n".write(to: root.appendingPathComponent("App/GatitaApp.swift"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try "secret".write(to: root.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8)
    return root
}

/// A date from an ISO 8601 string, such as "2026-10-08T12:00:00Z".
func isoDate(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

/// The mock Gatita API from Tests/MockServer, which the agent-loop tests call over HTTP.
enum MockGatita {
    static let port = ProcessInfo.processInfo.environment["MOCK_PORT"] ?? "8765"
    static let base = URL(string: "http://127.0.0.1:\(port)/v1")!

    /// Starts the mock and waits until it accepts connections. The caller stops it with terminate().
    static func start() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [RepoPaths.mockServer.path, port]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        guard waitUntilListening(timeout: 5) else {
            process.terminate()
            throw ToolError("the mock Gatita API did not start on port \(port)")
        }
        return process
    }

    /// Tries to connect to the port until it works, or the time runs out.
    private static func waitUntilListening(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let socketFD = socket(AF_INET, SOCK_STREAM, 0)
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(UInt16(port) ?? 8765).bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let connected = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            close(socketFD)
            if connected == 0 { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }
}
