import CoreGraphics
import Foundation

struct ManagedVirtualDisplaySpecification: Equatable {
    let width: Int
    let height: Int
    let refreshRate: Int
    let hiDPI: Bool

    var isValid: Bool {
        width >= 640
            && height >= 480
            && (15...240).contains(refreshRate)
    }
}

enum ManagedVirtualDisplayError: Error, LocalizedError, Equatable {
    case invalidSpecification
    case helperNotExecutable(String)
    case helperExited(Int32)
    case readinessTimedOut
    case invalidReadyFile

    var errorDescription: String? {
        switch self {
        case .invalidSpecification:
            return "The negotiated DisplayMesh virtual-display mode is invalid"
        case .helperNotExecutable(let path):
            return "DisplayMesh virtual-display helper is not executable: \(path)"
        case .helperExited(let status):
            return "DisplayMesh virtual-display helper exited before readiness (status \(status))"
        case .readinessTimedOut:
            return "Timed out waiting for the DisplayMesh virtual display"
        case .invalidReadyFile:
            return "DisplayMesh virtual-display helper returned an invalid display ID"
        }
    }
}

enum VirtualDisplayReadyFile {
    static func parse(_ data: Data) -> CGDirectDisplayID? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard let raw = UInt32(trimmed), raw != 0 else {
            return nil
        }

        return CGDirectDisplayID(raw)
    }
}

final class ManagedVirtualDisplayProcess {
    private var process: Process?
    private var readyFileURL: URL?

    private(set) var displayID: CGDirectDisplayID?

    func start(
        helperPath: String,
        specification: ManagedVirtualDisplaySpecification,
        timeoutSeconds: TimeInterval = 5
    ) async throws -> CGDirectDisplayID {
        guard specification.isValid else {
            throw ManagedVirtualDisplayError.invalidSpecification
        }

        guard process == nil else {
            if let displayID {
                return displayID
            }
            throw ManagedVirtualDisplayError.invalidReadyFile
        }

        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            throw ManagedVirtualDisplayError.helperNotExecutable(helperPath)
        }

        let readyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "displaymesh-virtual-display-\(UUID().uuidString).ready"
            )
        try? FileManager.default.removeItem(at: readyURL)

        let child = Process()
        child.executableURL = URL(fileURLWithPath: helperPath)
        child.arguments = [
            String(specification.width),
            String(specification.height),
            String(specification.refreshRate),
            specification.hiDPI ? "1" : "0",
            readyURL.path,
        ]
        child.standardOutput = FileHandle.standardOutput
        child.standardError = FileHandle.standardError

        do {
            try child.run()
        } catch {
            throw ManagedVirtualDisplayError.helperNotExecutable(helperPath)
        }

        process = child
        readyFileURL = readyURL

        let deadline =
            ProcessInfo.processInfo.systemUptime
            + max(timeoutSeconds, 0.1)

        do {
            while ProcessInfo.processInfo.systemUptime < deadline {
                try Task.checkCancellation()

                if let data = try? Data(contentsOf: readyURL) {
                    guard let displayID = VirtualDisplayReadyFile.parse(data) else {
                        if !data.isEmpty {
                            stop()
                            throw ManagedVirtualDisplayError.invalidReadyFile
                        }
                        try await Task.sleep(for: .milliseconds(50))
                        continue
                    }

                    self.displayID = displayID
                    try? FileManager.default.removeItem(at: readyURL)
                    readyFileURL = nil
                    return displayID
                }

                if !child.isRunning {
                    let status = child.terminationStatus
                    stop()
                    throw ManagedVirtualDisplayError.helperExited(status)
                }

                try await Task.sleep(for: .milliseconds(50))
            }
        } catch {
            stop()
            throw error
        }

        stop()
        throw ManagedVirtualDisplayError.readinessTimedOut
    }

    func detach() {
        try? readyFileURL.map {
            try FileManager.default.removeItem(at: $0)
        }
        readyFileURL = nil
        displayID = nil
        process = nil
    }

    func stop() {
        if let child = process, child.isRunning {
            child.terminate()
            child.waitUntilExit()
        }

        process = nil
        displayID = nil

        if let readyFileURL {
            try? FileManager.default.removeItem(at: readyFileURL)
        }
        self.readyFileURL = nil
    }

    deinit {
        if let child = process, child.isRunning {
            child.terminate()
        }
        if let readyFileURL {
            try? FileManager.default.removeItem(at: readyFileURL)
        }
    }
}
