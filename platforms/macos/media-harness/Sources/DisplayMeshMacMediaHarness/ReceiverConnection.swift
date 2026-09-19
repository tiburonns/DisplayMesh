import Foundation
import Network

final class ReceiverConnection {
    static let port = NWEndpoint.Port(rawValue: 49_655)!

    var onKeyframeRequest: (() -> Void)?
    var onInput: ((Data) -> Void)?
    var onTelemetry: ((Data) -> Void)?
    var onErrorMessage: ((Data) -> Void)?

    private let queue = DispatchQueue(
        label: "com.tiburonns.DisplayMesh.macHarness.receiver",
        qos: .userInteractive
    )
    private let videoGate = NSLock()

    private var connection: NWConnection?
    private var decoder = DMPFrameDecoder()
    private var nextSequence: UInt32 = 1
    private var videoSendInFlight = false

    private var pairingResponse: PairingResponse?
    private var pairingContinuation: CheckedContinuation<PairingResponse, Error>?
    private var panelDescriptor: ReceiverPanelDescriptor?
    private var panelContinuation: CheckedContinuation<ReceiverPanelDescriptor, Error>?

    func connect(host: String) async throws {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true

        let parameters = NWParameters(tls: nil, tcp: tcp)
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: Self.port,
            using: parameters
        )

        self.connection = connection

        try await withCheckedThrowingContinuation { continuation in
            var resolved = false

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }

                switch state {
                case .ready:
                    if !resolved {
                        resolved = true
                        continuation.resume()
                    }
                    receiveNext(on: connection)

                case .failed(let error):
                    if !resolved {
                        resolved = true
                        continuation.resume(throwing: error)
                    }
                    failWaiters(error)
                    clearVideoGate()

                case .cancelled:
                    if !resolved {
                        resolved = true
                        continuation.resume(throwing: DMPProtocolError.connectionClosed)
                    }
                    failWaiters(DMPProtocolError.connectionClosed)
                    clearVideoGate()

                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }

    func close() {
        connection?.cancel()
        connection = nil
        failWaiters(DMPProtocolError.connectionClosed)
        clearVideoGate()
    }

    func sendPairingRequest(peerName: String, code: String) throws {
        let request = PairingRequest(
            peerName: peerName,
            verificationCode: code,
            protocolVersion: Int(DMPFrame.version)
        )
        let payload = try JSONEncoder().encode(request)
        send(type: .pairing, payload: payload)
    }

    func waitForPairingResponse() async throws -> PairingResponse {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: DMPProtocolError.connectionClosed)
                    return
                }

                if let pairingResponse {
                    continuation.resume(returning: pairingResponse)
                } else {
                    pairingContinuation = continuation
                }
            }
        }
    }

    func waitForPanelDescriptor() async throws -> ReceiverPanelDescriptor {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: DMPProtocolError.connectionClosed)
                    return
                }

                if let panelDescriptor {
                    continuation.resume(returning: panelDescriptor)
                } else {
                    panelContinuation = continuation
                }
            }
        }
    }

    func canAcceptVideo() -> Bool {
        videoGate.lock()
        defer { videoGate.unlock() }
        return !videoSendInFlight && connection != nil
    }

    @discardableResult
    func sendVideoPacket(_ packet: DMPVideoPacket) -> Bool {
        let payload: Data
        do {
            payload = try packet.encoded()
        } catch {
            return false
        }

        videoGate.lock()
        guard !videoSendInFlight, connection != nil else {
            videoGate.unlock()
            return false
        }
        videoSendInFlight = true
        videoGate.unlock()

        queue.async { [weak self] in
            guard let self, let connection else {
                self?.clearVideoGate()
                return
            }

            do {
                let frame = try makeFrame(type: .video, payload: payload)
                let data = try frame.encoded()

                connection.send(
                    content: data,
                    completion: .contentProcessed { [weak self] error in
                        self?.clearVideoGate()
                        if let error {
                            self?.failWaiters(error)
                        }
                    }
                )
            } catch {
                clearVideoGate()
            }
        }

        return true
    }

    private func send(type: DMPMessageType, payload: Data) {
        queue.async { [weak self] in
            guard let self, let connection else { return }

            do {
                let frame = try makeFrame(type: type, payload: payload)
                connection.send(
                    content: try frame.encoded(),
                    completion: .contentProcessed { _ in }
                )
            } catch {
                failWaiters(error)
            }
        }
    }

    private func makeFrame(
        type: DMPMessageType,
        payload: Data
    ) throws -> DMPFrame {
        let frame = DMPFrame(
            type: type,
            flags: 0,
            sequence: nextSequence,
            payload: payload
        )
        nextSequence &+= 1
        return frame
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }

            if let data, !data.isEmpty {
                do {
                    decoder.append(data)
                    while let frame = try decoder.nextFrame() {
                        handle(frame)
                    }
                } catch {
                    failWaiters(error)
                    connection.cancel()
                    return
                }
            }

            if let error {
                failWaiters(error)
                connection.cancel()
                return
            }

            if isComplete {
                failWaiters(DMPProtocolError.connectionClosed)
                connection.cancel()
                return
            }

            receiveNext(on: connection)
        }
    }

    private func handle(_ frame: DMPFrame) {
        switch frame.type {
        case .pairing:
            do {
                let response = try JSONDecoder().decode(
                    PairingResponse.self,
                    from: frame.payload
                )
                pairingResponse = response
                pairingContinuation?.resume(returning: response)
                pairingContinuation = nil
            } catch {
                pairingContinuation?.resume(throwing: error)
                pairingContinuation = nil
            }

        case .panelDescriptor:
            do {
                let panel = try JSONDecoder().decode(
                    ReceiverPanelDescriptor.self,
                    from: frame.payload
                )
                panelDescriptor = panel
                panelContinuation?.resume(returning: panel)
                panelContinuation = nil
            } catch {
                panelContinuation?.resume(throwing: error)
                panelContinuation = nil
            }

        case .keyframeRequest:
            onKeyframeRequest?()

        case .input:
            onInput?(frame.payload)

        case .telemetry:
            onTelemetry?(frame.payload)

        case .error:
            onErrorMessage?(frame.payload)

        case .hello, .capabilities, .video:
            break
        }
    }

    private func failWaiters(_ error: Error) {
        pairingContinuation?.resume(throwing: error)
        pairingContinuation = nil
        panelContinuation?.resume(throwing: error)
        panelContinuation = nil
    }

    private func clearVideoGate() {
        videoGate.lock()
        videoSendInFlight = false
        videoGate.unlock()
    }
}
