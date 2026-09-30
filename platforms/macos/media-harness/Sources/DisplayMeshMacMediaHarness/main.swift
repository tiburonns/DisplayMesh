import CoreGraphics
import Foundation
import ScreenCaptureKit

private struct Options {
    var listDisplays = false
    var receiverHost: String?
    var displayID: CGDirectDisplayID?
    var framesPerSecond = 60
    var bitrateMbps = 24
    var width: Int?
    var height: Int?
    var durationSeconds: Int?
    var reconnectAttempts = HostReconnectPolicy.defaultMaximumRetries

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]

            func nextValue() throws -> String {
                guard index + 1 < arguments.count else {
                    throw CLIError.missingValue(argument)
                }
                index += 1
                return arguments[index]
            }

            switch argument {
            case "--list":
                options.listDisplays = true
            case "--host":
                options.receiverHost = try nextValue()
            case "--display":
                let raw = try nextValue()
                guard let value = UInt32(raw) else {
                    throw CLIError.invalidValue(argument, raw)
                }
                options.displayID = value
            case "--fps":
                let raw = try nextValue()
                guard let value = Int(raw), (15...240).contains(value) else {
                    throw CLIError.invalidValue(argument, raw)
                }
                options.framesPerSecond = value
            case "--bitrate":
                let raw = try nextValue()
                guard let value = Int(raw), (2...200).contains(value) else {
                    throw CLIError.invalidValue(argument, raw)
                }
                options.bitrateMbps = value
            case "--width":
                let raw = try nextValue()
                guard let value = Int(raw), value > 0 else {
                    throw CLIError.invalidValue(argument, raw)
                }
                options.width = value
            case "--height":
                let raw = try nextValue()
                guard let value = Int(raw), value > 0 else {
                    throw CLIError.invalidValue(argument, raw)
                }
                options.height = value
            case "--seconds":
                let raw = try nextValue()
                guard let value = Int(raw), value > 0 else {
                    throw CLIError.invalidValue(argument, raw)
                }
                options.durationSeconds = value
            case "--reconnect-attempts":
                let raw = try nextValue()
                guard let value = Int(raw),
                      (0...HostReconnectPolicy.maximumSupportedRetries).contains(value) else {
                    throw CLIError.invalidValue(argument, raw)
                }
                options.reconnectAttempts = value
            case "--help", "-h":
                throw CLIError.help
            default:
                throw CLIError.unknownArgument(argument)
            }

            index += 1
        }

        return options
    }
}

private enum CLIError: Error, LocalizedError {
    case help
    case missingValue(String)
    case invalidValue(String, String)
    case unknownArgument(String)
    case receiverRequired

    var errorDescription: String? {
        switch self {
        case .help:
            return nil
        case .missingValue(let flag):
            return "Missing value after \(flag)"
        case .invalidValue(let flag, let value):
            return "Invalid value for \(flag): \(value)"
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        case .receiverRequired:
            return "--host <iPhone-or-iPad-IP> is required unless --list is used"
        }
    }
}

@main
struct DisplayMeshMacMediaHarness {
    static func main() async {
        do {
            let options = try Options.parse(CommandLine.arguments)

            if options.listDisplays {
                try await listDisplays()
                return
            }

            guard let receiverHost = options.receiverHost else {
                throw CLIError.receiverRequired
            }

            try await run(
                options: options,
                receiverHost: receiverHost
            )
        } catch CLIError.help {
            printUsage()
        } catch {
            fputs("DisplayMesh harness error: \(error.localizedDescription)\n", stderr)
            printUsage()
            exit(1)
        }
    }

    private static func listDisplays() async throws {
        let displays = try await DisplayCaptureEncoder.availableDisplays()

        if displays.isEmpty {
            print("No displays are currently available to ScreenCaptureKit.")
            return
        }

        print("Available displays:")
        for display in displays {
            print(
                "  id=\(display.displayID)  \(display.width)x\(display.height)"
            )
        }
    }

    private static func run(
        options: Options,
        receiverHost: String
    ) async throws {
        var completedRetries = 0

        while true {
            do {
                try await runOnce(
                    options: options,
                    receiverHost: receiverHost
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard HostReconnectPolicy.shouldRetry(
                    error,
                    completedRetries: completedRetries,
                    maximumRetries: options.reconnectAttempts
                ) else {
                    throw error
                }

                completedRetries += 1
                let delay = HostReconnectPolicy.delaySeconds(
                    forRetryNumber: completedRetries
                )

                fputs(
                    "transport: \(error.localizedDescription) — reconnect " +
                    "\(completedRetries)/\(options.reconnectAttempts) in " +
                    String(format: "%.1f", delay) + " s\n",
                    stderr
                )

                try await Task.sleep(
                    nanoseconds: UInt64(
                        (delay * 1_000_000_000).rounded()
                    )
                )
            }
        }
    }

    private static func runOnce(
        options: Options,
        receiverHost: String
    ) async throws {
        let receiver = ReceiverConnection()
        defer { receiver.close() }

        print("Connecting to DisplayMesh receiver at \(receiverHost):49655 …")
        try await receiver.connect(host: receiverHost)

        let hello = try await receiver.waitForReceiverHello()
        guard hello.isValid else {
            throw DMPProtocolError.invalidReceiverHello
        }

        let identity = try HostIdentityStore.loadOrCreate()
        let verificationCode = String(
            format: "%06d",
            Int.random(in: 0...999_999)
        )
        let request = try identity.makePairingRequest(
            peerName: Host.current().localizedName ?? "Mac",
            verificationCode: verificationCode,
            challenge: hello.challenge
        )

        try receiver.sendPairingRequest(request)

        print("")
        print("PAIRING CODE: \(verificationCode)")
        print(
            "HOST IDENTITY: " +
            identity.fingerprint.uppercased()
        )
        print("Confirm both values on the iPhone/iPad receiver.")
        print("")

        let pairing = try await receiver.waitForPairingResponse()
        guard pairing.accepted else {
            throw DMPProtocolError.pairingRejected
        }

        print("Paired with \(pairing.receiverName). Negotiating receiver capabilities …")
        let capabilities = try await receiver.waitForReceiverCapabilities()
        guard capabilities.supportsDevelopmentHost else {
            throw DMPProtocolError.incompatibleReceiverCapabilities
        }

        print(
            "Receiver capabilities: codecs=" +
            capabilities.codecs.joined(separator: ",") +
            " bindings=" +
            capabilities.connectionBindings.joined(separator: ",") +
            " input=" +
            capabilities.inputKinds.joined(separator: ",") +
            (capabilities.encryptedTransport
                ? " | encrypted"
                : " | plaintext development transport")
        )

        let panel = try await receiver.waitForPanelDescriptor()

        let targetFPS = min(
            options.framesPerSecond,
            max(panel.maximumFramesPerSecond, 1)
        )

        print(
            "Receiver panel: \(panel.pixelWidth)x\(panel.pixelHeight) " +
            "@ up to \(panel.maximumFramesPerSecond) Hz, " +
            "scale \(String(format: "%.2f", panel.nativeScale))"
        )

        let encoder = DisplayCaptureEncoder()
        encoder.shouldEncodeFrame = { [weak receiver] in
            receiver?.canAcceptVideo() ?? false
        }

        encoder.onPacket = { [weak receiver, weak encoder] packet in
            guard let receiver else { return false }
            let accepted = receiver.sendVideoPacket(packet)
            if !accepted {
                encoder?.requestKeyframe()
            }
            return accepted
        }

        encoder.onMetrics = { metrics in
            print(
                String(
                    format:
                        "host %.1f FPS | %.1f Mbps | captured %llu | " +
                        "drop pre %llu | drop post %llu | keyframes %llu",
                    metrics.framesPerSecond,
                    metrics.megabitsPerSecond,
                    metrics.capturedFrames,
                    metrics.droppedBeforeEncode,
                    metrics.droppedAfterEncode,
                    metrics.keyframes
                )
            )
        }

        encoder.onError = { message in
            fputs("media: \(message)\n", stderr)
        }

        receiver.onKeyframeRequest = { [weak encoder] in
            encoder?.requestKeyframe()
        }

        receiver.onErrorMessage = { payload in
            let message = String(data: payload, encoding: .utf8) ?? "<binary error>"
            fputs("receiver: \(message)\n", stderr)
        }

        var adaptiveController = ReceiverAdaptiveController(
            initialBitrateMbps: options.bitrateMbps,
            maximumBitrateMbps: max(options.bitrateMbps, 120),
            targetFramesPerSecond: targetFPS
        )

        receiver.onReceiverTelemetry = { [weak encoder, weak receiver] telemetry in
            print(
                String(
                    format:
                        "receiver %.1f FPS | %.1f Mbps | %.1f ms decode | " +
                        "decoded %llu | dropped %llu%@",
                    telemetry.framesPerSecond,
                    telemetry.megabitsPerSecond,
                    telemetry.averageDecodeMilliseconds,
                    telemetry.decodedFrames,
                    telemetry.droppedFrames,
                    telemetry.hardwareAccelerated == true ? " | HW" : ""
                )
            )

            if let decision = adaptiveController.update(telemetry) {
                encoder?.setBitrate(mbps: decision.bitrateMbps)
                if decision.requestKeyframe {
                    encoder?.requestKeyframe()
                }

                if let encoder {
                    Task { [weak encoder] in
                        guard let encoder else { return }
                        do {
                            if let dimensions = try await encoder.applyRasterScale(
                                decision.rasterScale
                            ) {
                                print(
                                    "adaptive raster -> " +
                                    "\(dimensions.width)x\(dimensions.height) " +
                                    "(\(Int((decision.rasterScale * 100).rounded()))%)"
                                )
                            }
                        } catch {
                            fputs(
                                "adaptive raster: \(error.localizedDescription)\n",
                                stderr
                            )
                            await encoder.stop()
                            receiver?.close()
                        }
                    }
                }

                print(
                    "adaptive bitrate -> \(decision.bitrateMbps) Mbps" +
                    (decision.requestKeyframe ? " + keyframe" : "")
                )
            }
        }

        let capture = try await encoder.start(
            displayID: options.displayID,
            width: options.width,
            height: options.height,
            framesPerSecond: targetFPS,
            bitrateMbps: options.bitrateMbps
        )

        let inputBridge = MacInputBridge(
            targetBounds: CGDisplayBounds(capture.display.displayID)
        )
        inputBridge.onError = { message in
            fputs("input: \(message)\n", stderr)
        }

        let accessibilityReady =
            inputBridge.requestAccessibilityIfNeeded()

        if accessibilityReady {
            print("Touch control: Accessibility permission ready.")
        } else {
            print(
                "Touch control: macOS requested Accessibility permission. " +
                "Grant it in System Settings to enable pointer/scroll input."
            )
        }

        receiver.onInput = { [weak inputBridge] payload in
            inputBridge?.handle(payload)
        }

        print(
            "Streaming display \(capture.display.displayID) at " +
            "\(capture.width)x\(capture.height) @ \(targetFPS) FPS, " +
            "\(options.bitrateMbps) Mbps."
        )
        print("Touch: one finger = click/drag, two fingers = scroll.")
        print("Press Control-C to stop.")

        do {
            try await monitorSession(
                receiver: receiver,
                durationSeconds: options.durationSeconds
            )
        } catch {
            inputBridge.reset()
            await encoder.stop()
            throw error
        }

        inputBridge.reset()
        await encoder.stop()
    }

    private static func monitorSession(
        receiver: ReceiverConnection,
        durationSeconds: Int?
    ) async throws {
        let startedAt = ProcessInfo.processInfo.systemUptime

        while true {
            try Task.checkCancellation()

            guard receiver.isConnected else {
                throw receiver.lastDisconnectError
                    ?? DMPProtocolError.connectionClosed
            }

            if let durationSeconds,
               ProcessInfo.processInfo.systemUptime - startedAt
                    >= Double(durationSeconds) {
                return
            }

            try await Task.sleep(
                nanoseconds: HostReconnectPolicy.sessionPollNanoseconds
            )
        }
    }

    private static func printUsage() {
        print(
            """
            DisplayMesh macOS media harness

            Usage:
              displaymesh-mac-media-harness --list
              displaymesh-mac-media-harness --host <receiver-ip> [options]

            Options:
              --display <id>     ScreenCaptureKit display ID (default: first)
              --fps <15-240>     Target FPS (default: 60, capped by receiver)
              --bitrate <2-200>  H.264 bitrate in Mbps (default: 24)
              --width <pixels>   Encoded width (default: captured display width)
              --height <pixels>  Encoded height (default: captured display height)
              --seconds <n>      Stop automatically after n seconds
              --reconnect-attempts <0-10>
                                  Retry transient disconnects (default: 3)
              --help             Show this help

            The receiver must already be listening in the DisplayMesh
            iPhone/iPad app. This development harness uses plaintext TCP;
            production TLS is still a release blocker.
            """
        )
    }
}
