import Foundation
import Network
import UIKit

enum ReceiverListenerState: Equatable {
    case stopped
    case starting
    case ready(port: UInt16)
    case waiting(String)
    case connected(String)
    case failed(String)
}

final class ReceiverListener {
    static let port = NWEndpoint.Port(rawValue: 49_655)!

    var onState: ((ReceiverListenerState) -> Void)?
    var onFrame: ((DMPFrame) -> Void)?

    private let queue = DispatchQueue(
        label: "com.tiburonns.DisplayMesh.receiver.transport",
        qos: .userInteractive
    )

    private var listener: NWListener?
    private var connection: NWConnection?
    private var decoder = DMPFrameDecoder()
    private var incomingSequence = DMPSequenceTracker()
    private var nextSequence: UInt32 = 1
    private var secureSession: DMPSecureSession?

    func start() throws {
        guard listener == nil else { return }

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true

        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.allowLocalEndpointReuse = true

        let newListener = try NWListener(using: parameters, on: Self.port)
        newListener.newConnectionLimit = 1
        newListener.service = NWListener.Service(
            name: "DisplayMesh",
            type: "_displaymesh._tcp"
        )

        newListener.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }

        newListener.newConnectionHandler = { [weak self] newConnection in
            self?.accept(newConnection)
        }

        listener = newListener
        publish(.starting)
        newListener.start(queue: queue)
    }

    func activateSecureSession(_ session: DMPSecureSession) {
        queue.async { [weak self] in
            self?.secureSession = session
        }
    }

    func disconnectCurrent() {
        queue.async { [weak self] in
            guard let self, let activeConnection = connection else { return }

            connection = nil
            activeConnection.stateUpdateHandler = nil
            activeConnection.cancel()
            decoder = DMPFrameDecoder()
            incomingSequence.reset()
            nextSequence = 1
            secureSession = nil

            if listener != nil {
                publish(.ready(port: Self.port.rawValue))
            } else {
                publish(.stopped)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }

            connection?.cancel()
            connection = nil
            listener?.cancel()
            listener = nil
            decoder = DMPFrameDecoder()
            incomingSequence.reset()
            nextSequence = 1
            secureSession = nil
            publish(.stopped)
        }
    }

    func send(type: DMPMessageType, payload: Data, flags: UInt16 = 0) {
        queue.async { [weak self] in
            guard let self, let connection else { return }

            do {
                let sequence = nextSequence
                let wireFlags: UInt16
                let wirePayload: Data

                if let secureSession {
                    wireFlags =
                        flags | DMPFrame.encryptedPayloadFlag
                    wirePayload = try secureSession.seal(
                        payload,
                        type: type,
                        flags: flags,
                        sequence: sequence
                    )
                } else {
                    wireFlags = flags
                    wirePayload = payload
                }

                let frame = DMPFrame(
                    type: type,
                    flags: wireFlags,
                    sequence: sequence,
                    payload: wirePayload
                )
                let data = try frame.encoded()
                nextSequence &+= 1

                connection.send(
                    content: data,
                    completion: .contentProcessed { [weak self, weak connection] error in
                        guard let self, let connection, let error else { return }
                        queue.async {
                            guard self.connection === connection else { return }
                            self.publish(.failed(error.localizedDescription))
                            connection.cancel()
                        }
                    }
                )
            } catch {
                publish(.failed(error.localizedDescription))
                connection.cancel()
            }
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .setup:
            publish(.starting)
        case .waiting(let error):
            publish(.waiting(error.localizedDescription))
        case .ready:
            publish(.ready(port: Self.port.rawValue))
        case .failed(let error):
            publish(.failed(error.localizedDescription))
            listener?.cancel()
            listener = nil
        case .cancelled:
            publish(.stopped)
        @unknown default:
            publish(.waiting("Unknown listener state"))
        }
    }

    private func accept(_ newConnection: NWConnection) {
        // Never let an unsolicited second peer evict an active session.
        // The current receiver intentionally supports one transport connection
        // at a time; the user must end it before another peer can connect.
        guard connection == nil else {
            newConnection.cancel()
            return
        }

        connection = newConnection
        decoder = DMPFrameDecoder()
        incomingSequence.reset()
        nextSequence = 1
        secureSession = nil

        newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
            guard let self, let newConnection else { return }
            guard self.connection === newConnection else { return }

            switch state {
            case .ready:
                publish(.connected(String(describing: newConnection.endpoint)))
                receiveNext(on: newConnection)
            case .waiting(let error):
                publish(.waiting(error.localizedDescription))
            case .failed(let error):
                publish(.failed(error.localizedDescription))
                newConnection.cancel()
                if connection === newConnection {
                    connection = nil
                }
            case .cancelled:
                if connection === newConnection {
                    connection = nil
                    publish(.ready(port: Self.port.rawValue))
                }
            default:
                break
            }
        }

        newConnection.start(queue: queue)
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            guard self.connection === connection else { return }

            if let data, !data.isEmpty {
                do {
                    decoder.append(data)
                    while let frame = try decoder.nextFrame() {
                        try incomingSequence.accept(frame.sequence)
                        let clearFrame =
                            try decodeInboundFrame(frame)
                        publish(clearFrame)
                    }
                } catch {
                    publish(.failed(error.localizedDescription))
                    connection.cancel()
                    return
                }
            }

            if let error {
                publish(.failed(error.localizedDescription))
                connection.cancel()
                return
            }

            if isComplete {
                connection.cancel()
                return
            }

            receiveNext(on: connection)
        }
    }

    private func decodeInboundFrame(
        _ frame: DMPFrame
    ) throws -> DMPFrame {
        if let secureSession {
            guard frame.flags & DMPFrame.encryptedPayloadFlag != 0 else {
                throw DMPSecureSessionError
                    .plaintextFrameAfterActivation
            }

            let plaintext = try secureSession.open(
                frame.payload,
                type: frame.type,
                flags: frame.flags,
                sequence: frame.sequence
            )
            try frame.type.validatePayloadSize(
                plaintext.count
            )

            return DMPFrame(
                type: frame.type,
                flags:
                    frame.flags
                    & ~DMPFrame.encryptedPayloadFlag,
                sequence: frame.sequence,
                payload: plaintext
            )
        }

        guard frame.flags & DMPFrame.encryptedPayloadFlag == 0 else {
            throw DMPSecureSessionError
                .encryptedFrameBeforeActivation
        }
        return frame
    }

    private func publish(_ state: ReceiverListenerState) {
        DispatchQueue.main.async { [weak self] in
            self?.onState?(state)
        }
    }

    private func publish(_ frame: DMPFrame) {
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(frame)
        }
    }
}
