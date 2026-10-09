//
//  BackgroundProcess.swift
//  Gatita
//

#if os(macOS)
import Foundation

/// One allowed command that runs in the background, inside the same sandbox as a foreground command.
/// Its output is handed over as it is written, and `onExit` runs when it ends. It has no time limit: the user stops it.
final class BackgroundProcess {
    private let process: Process
    private let pipe = Pipe()

    init(arguments: [String], root: URL) {
        process = CommandRunner.makeProcess(arguments, in: root)
    }

    func start(onOutput: @escaping @Sendable (String) -> Void,
               onExit: @escaping @Sendable (Int32) -> Void) throws {
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            onOutput(String(decoding: data, as: UTF8.self))
        }
        process.terminationHandler = { [pipe] finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = pipe.fileHandleForReading.readDataToEndOfFile()
            if !rest.isEmpty {
                onOutput(String(decoding: rest, as: UTF8.self))
            }
            onExit(finished.terminationStatus)
        }
        try process.run()
    }

    func stop() {
        if process.isRunning {
            process.terminate()
        }
    }
}
#endif
