import Foundation
import Network
import UIKit

@MainActor
final class ReceiverListener {
    static let port: NWEndpoint.Port = 49_655

    var onConnection: ((NWConnection) -> Void)?
    var onState: ((NWListener.State) -> Void)?

    private var listener: NWListener?

    func start() throws {
        guard listener == nil else {
            return
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: Self.port)
        listener.service = NWListener.Service(
            name: UIDevice.current.name,
            type: "_displaymesh._tcp"
        )

        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.onState?(state)
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.onConnection?(connection)
            }
        }

        listener.start(queue: .global(qos: .userInteractive))
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}
