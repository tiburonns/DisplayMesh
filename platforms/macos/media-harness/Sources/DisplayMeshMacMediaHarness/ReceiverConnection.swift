import Foundation
import Network

final class ReceiverConnection {
    static let port = NWEndpoint.Port(rawValue: 49_655)!

    var onKeyframeRequest: (() -> Void)?
    var onInput: ((Data) -> Void)?
    var onReceiverTelemetry: ((ReceiverTelemetry) -> Void)?
    var onErrorMessage: ((Data) -> Void)?

    private let queue = DispatchQueue(
        label: "com.tiburonns.DisplayMesh.macHarness.receiver",
        qos: .userInteractive
    )
    private let videoGate = NSLock()
    private let phaseLock = NSLock()

    private var connection: NWConnection?
    private var decoder = DMPFrameDecoder()
    private var incomingSequence = DMPSequenceTracker()
    private var nextSequence: UInt32 = 1
    private var videoSendInFlight = false
    private var connectionReady = false
    private var protocolPhaseStorage: HostReceiverPhase = .awaitingHello

    private var receiverHello: ReceiverHello?
    private var helloContinuation: CheckedContinuation<ReceiverHello, Error>?
    private var helloWaitToken: UUID?

    private var pairingResponse: PairingResponse?
    private var pairingContinuation: CheckedContinuation<PairingResponse, Error>?
    private var pairingWaitToken: UUID?

    private var panelDescriptor: ReceiverPanelDescriptor?
    private var panelContinuation: CheckedContinuation<ReceiverPanelDescriptor, Error>?
    private var panelWaitToken: UUID?

    func connect(host: String) async throws {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true

        let parameters = NWParameters(tls: nil, tcp: tcp)
        let newConnection = NWConnection(
            host: NWEndpoint.Host(host),
            port: Self.port,
            using: parameters
        )

        resetProtocolState()
        connection = newConnection
        setConnectionReady(false)

        try await withCheckedThrowingContinuation { continuation in
            var resolved = false

            newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
                guard let self, let newConnection else { return }
                guard connection === newConnection else { return }

                switch state {
                case .ready:
                    setConnectionReady(true)
                    if !resolved {
                        resolved = true
                        continuation.resume()
                    }
                    receiveNext(on: newConnection)

                case .failed(let error):
                    if !resolved {
                        resolved = true
                        continuation.resume(throwing: error)
                    }
                    handleTransportFailure(error, connection: newConnection)

                case .cancelled:
                    let error = DMPProtocolError.connectionClosed
                    if !resolved {
                        resolved = true
                        continuation.resume(throwing: error)
                    }
                    handleTransportFailure(error, connection: newConnection)

                default:
                    break
                }
            }

            newConnection.start(queue: queue)
        }
    }

    func close() {
        queue.async { [weak self] in
            guard let self else { return }
            connection?.cancel()
            connection = nil
            setConnectionReady(false)
            failWaiters(DMPProtocolError.connectionClosed)
            clearVideoGate()
            resetProtocolState()
        }
    }

    func waitForReceiverHello(
        timeoutSeconds: TimeInterval = 10
    ) async throws -> ReceiverHello {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(
                        throwing: DMPProtocolError.connectionClosed
                    )
                    return
                }

                if let receiverHello {
                    continuation.resume(returning: receiverHello)
                    return
                }

                if helloContinuation != nil {
                    continuation.resume(
                        throwing: DMPProtocolError.timeout(
                            "previous receiver hello waiter"
                        )
                    )
                    return
                }

                let token = UUID()
                helloWaitToken = token
                helloContinuation = continuation

                queue.asyncAfter(
                    deadline: .now() + timeoutSeconds
                ) { [weak self] in
                    guard let self,
                          helloWaitToken == token,
                          let pending = helloContinuation else {
                        return
                    }

                    helloWaitToken = nil
                    helloContinuation = nil
                    pending.resume(
                        throwing: DMPProtocolError.timeout(
                            "receiver hello challenge"
                        )
                    )
                }
            }
        }
    }

    func sendPairingRequest(_ request: PairingRequest) throws {
        guard request.hasValidShape else {
            throw DMPProtocolError.invalidPairingRequest
        }
        let phase = currentProtocolPhase()
        guard phase == .readyToPair else {
            throw DMPProtocolError.invalidSessionPhase(
                "pairing request while \(phase)"
            )
        }

        setProtocolPhase(.awaitingPairingResponse)
        let payload = try JSONEncoder().encode(request)
        send(type: .pairing, payload: payload)
    }

    func waitForPairingResponse(
        timeoutSeconds: TimeInterval = 30
    ) async throws -> PairingResponse {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: DMPProtocolError.connectionClosed)
                    return
                }

                if let pairingResponse {
                    continuation.resume(returning: pairingResponse)
                    return
                }

                if pairingContinuation != nil {
                    continuation.resume(
                        throwing: DMPProtocolError.timeout("previous pairing waiter")
                    )
                    return
                }

                let token = UUID()
                pairingWaitToken = token
                pairingContinuation = continuation

                queue.asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                    guard let self,
                          pairingWaitToken == token,
                          let pending = pairingContinuation else {
                        return
                    }

                    pairingWaitToken = nil
                    pairingContinuation = nil
                    pending.resume(
                        throwing: DMPProtocolError.timeout("pairing approval")
                    )
                }
            }
        }
    }

    func waitForPanelDescriptor(
        timeoutSeconds: TimeInterval = 15
    ) async throws -> ReceiverPanelDescriptor {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: DMPProtocolError.connectionClosed)
                    return
                }

                if let panelDescriptor {
                    continuation.resume(returning: panelDescriptor)
                    return
                }

                if panelContinuation != nil {
                    continuation.resume(
                        throwing: DMPProtocolError.timeout("previous panel waiter")
                    )
                    return
                }

                let token = UUID()
                panelWaitToken = token
                panelContinuation = continuation

                queue.asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                    guard let self,
                          panelWaitToken == token,
                          let pending = panelContinuation else {
                        return
                    }

                    panelWaitToken = nil
                    panelContinuation = nil
                    pending.resume(
                        throwing: DMPProtocolError.timeout("receiver panel descriptor")
                    )
                }
            }
        }
    }

    func canAcceptVideo() -> Bool {
        videoGate.lock()
        defer { videoGate.unlock() }
        return connectionReady && !videoSendInFlight
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
        guard connectionReady, !videoSendInFlight else {
            videoGate.unlock()
            return false
        }
        videoSendInFlight = true
        videoGate.unlock()

        queue.async { [weak self] in
            guard let self, let activeConnection = connection else {
                self?.clearVideoGate()
                return
            }

            do {
                let data = try makeEncodedFrame(
                    type: .video,
                    payload: payload
                )

                activeConnection.send(
                    content: data,
                    completion: .contentProcessed { [weak self, weak activeConnection] error in
                        guard let self else { return }
                        clearVideoGate()

                        guard let error, let activeConnection else { return }
                        queue.async {
                            handleTransportFailure(
                                error,
                                connection: activeConnection
                            )
                        }
                    }
                )
            } catch {
                clearVideoGate()
                failWaiters(error)
            }
        }

        return true
    }

    private func send(type: DMPMessageType, payload: Data) {
        queue.async { [weak self] in
            guard let self, let activeConnection = connection else { return }

            do {
                let data = try makeEncodedFrame(
                    type: type,
                    payload: payload
                )
                activeConnection.send(
                    content: data,
                    completion: .contentProcessed { [weak self, weak activeConnection] error in
                        guard let self, let error, let activeConnection else { return }
                        queue.async {
                            handleTransportFailure(
                                error,
                                connection: activeConnection
                            )
                        }
                    }
                )
            } catch {
                failWaiters(error)
            }
        }
    }

    private func makeEncodedFrame(
        type: DMPMessageType,
        payload: Data
    ) throws -> Data {
        let frame = DMPFrame(
            type: type,
            flags: 0,
            sequence: nextSequence,
            payload: payload
        )
        let encoded = try frame.encoded()
        nextSequence &+= 1
        return encoded
    }

    private func receiveNext(on activeConnection: NWConnection) {
        activeConnection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self, weak activeConnection] data, _, isComplete, error in
            guard let self, let activeConnection else { return }
            guard connection === activeConnection else { return }

            if let data, !data.isEmpty {
                do {
                    decoder.append(data)
                    while let frame = try decoder.nextFrame() {
                        try incomingSequence.accept(frame.sequence)
                        try handle(frame)
                    }
                } catch {
                    handleTransportFailure(error, connection: activeConnection)
                    return
                }
            }

            if let error {
                handleTransportFailure(error, connection: activeConnection)
                return
            }

            if isComplete {
                handleTransportFailure(
                    DMPProtocolError.connectionClosed,
                    connection: activeConnection
                )
                return
            }

            receiveNext(on: activeConnection)
        }
    }

    private func handle(_ frame: DMPFrame) throws {
        let phase = currentProtocolPhase()
        guard HostProtocolGate.permits(
            frame.type,
            phase: phase
        ) else {
            throw DMPProtocolError.invalidSessionPhase(
                "\(phase) received \(frame.type)"
            )
        }

        switch frame.type {
        case .hello:
            do {
                let hello = try JSONDecoder().decode(
                    ReceiverHello.self,
                    from: frame.payload
                )
                guard hello.isValid else {
                    throw DMPProtocolError.invalidReceiverHello
                }

                receiverHello = hello
                setProtocolPhase(.readyToPair)
                helloWaitToken = nil
                helloContinuation?.resume(returning: hello)
                helloContinuation = nil
            } catch {
                helloWaitToken = nil
                helloContinuation?.resume(throwing: error)
                helloContinuation = nil
            }

        case .pairing:
            do {
                let response = try JSONDecoder().decode(
                    PairingResponse.self,
                    from: frame.payload
                )
                guard response.protocolVersion == Int(DMPFrame.version) else {
                    throw DMPProtocolError.unsupportedVersion(
                        UInt8(clamping: response.protocolVersion)
                    )
                }
                guard let challenge = receiverHello?.challenge,
                      response.isValid(expectedChallenge: challenge) else {
                    throw DMPProtocolError.invalidPairingResponse
                }
                pairingResponse = response
                setProtocolPhase(
                    response.accepted
                        ? .awaitingPanel
                        : .readyToPair
                )
                pairingWaitToken = nil
                pairingContinuation?.resume(returning: response)
                pairingContinuation = nil
            } catch {
                pairingWaitToken = nil
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
                setProtocolPhase(.streaming)
                panelWaitToken = nil
                panelContinuation?.resume(returning: panel)
                panelContinuation = nil
            } catch {
                panelWaitToken = nil
                panelContinuation?.resume(throwing: error)
                panelContinuation = nil
            }

        case .keyframeRequest:
            onKeyframeRequest?()

        case .input:
            onInput?(frame.payload)

        case .telemetry:
            do {
                let telemetry = try JSONDecoder().decode(
                    ReceiverTelemetry.self,
                    from: frame.payload
                )
                guard telemetry.protocolVersion == ReceiverTelemetry.version else {
                    throw DMPProtocolError.unsupportedVersion(
                        UInt8(clamping: telemetry.protocolVersion)
                    )
                }
                guard telemetry.isValid else {
                    throw DMPProtocolError.invalidReceiverTelemetry
                }
                onReceiverTelemetry?(telemetry)
            } catch {
                onErrorMessage?(Data(error.localizedDescription.utf8))
            }

        case .error:
            onErrorMessage?(frame.payload)

        case .capabilities, .video:
            break
        }
    }

    private func handleTransportFailure(
        _ error: Error,
        connection failedConnection: NWConnection
    ) {
        guard connection === failedConnection else { return }

        setConnectionReady(false)
        connection = nil
        failedConnection.cancel()
        failWaiters(error)
        clearVideoGate()
    }

    private func failWaiters(_ error: Error) {
        helloWaitToken = nil
        helloContinuation?.resume(throwing: error)
        helloContinuation = nil

        pairingWaitToken = nil
        pairingContinuation?.resume(throwing: error)
        pairingContinuation = nil

        panelWaitToken = nil
        panelContinuation?.resume(throwing: error)
        panelContinuation = nil
    }

    private func resetProtocolState() {
        decoder = DMPFrameDecoder()
        incomingSequence.reset()
        nextSequence = 1
        receiverHello = nil
        setProtocolPhase(.awaitingHello)
        helloWaitToken = nil
        pairingResponse = nil
        panelDescriptor = nil
        pairingWaitToken = nil
        panelWaitToken = nil
    }

    private func currentProtocolPhase() -> HostReceiverPhase {
        phaseLock.lock()
        defer { phaseLock.unlock() }
        return protocolPhaseStorage
    }

    private func setProtocolPhase(_ phase: HostReceiverPhase) {
        phaseLock.lock()
        protocolPhaseStorage = phase
        phaseLock.unlock()
    }

    private func setConnectionReady(_ ready: Bool) {
        videoGate.lock()
        connectionReady = ready
        if !ready {
            videoSendInFlight = false
        }
        videoGate.unlock()
    }

    private func clearVideoGate() {
        videoGate.lock()
        videoSendInFlight = false
        videoGate.unlock()
    }
}
