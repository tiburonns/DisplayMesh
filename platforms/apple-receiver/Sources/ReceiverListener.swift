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

    func start() throws {
        guard listener == nil else { return }

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true

        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.allowLocalEndpointReuse = true

        let newListener = try NWListener(using: parameters, on: Self.port)
        newListener.newConnectionLimit = 1
        newListener.service = NWListener.Service(
            name: UIDevice.current.name,
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
            publish(.stopped)
        }
    }

    func send(type: DMPMessageType, payload: Data, flags: UInt16 = 0) {
        queue.async { [weak self] in
            guard let self, let connection else { return }

            let frame = DMPFrame(
                type: type,
                flags: flags,
                sequence: nextSequence,
                payload: payload
            )
            nextSequence &+= 1

            guard let data = try? frame.encoded() else { return }
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
        connection?.cancel()
        connection = newConnection
        decoder = DMPFrameDecoder()
        incomingSequence.reset()
        nextSequence = 1

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
                        publish(frame)
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
