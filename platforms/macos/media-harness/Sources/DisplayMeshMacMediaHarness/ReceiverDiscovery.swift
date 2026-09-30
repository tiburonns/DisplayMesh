import Foundation
import Network

enum ReceiverDiscoveryCardinality: Equatable {
    case none
    case one
    case multiple(Int)
}

enum ReceiverDiscoveryPolicy {
    static let serviceType =
        "_displaymesh._tcp"
    static let defaultTimeoutSeconds:
        TimeInterval = 5

    static func classify(
        count: Int
    ) -> ReceiverDiscoveryCardinality {
        if count <= 0 {
            return .none
        }
        if count == 1 {
            return .one
        }
        return .multiple(count)
    }
}

enum ReceiverDiscoveryError:
    Error,
    LocalizedError,
    Equatable {
    case noReceiverFound
    case multipleReceiversFound(Int)
    case browserFailed(String)

    var errorDescription: String? {
        switch self {
        case .noReceiverFound:
            return "No DisplayMesh receiver was discovered on the local network"
        case .multipleReceiversFound(let count):
            return "Found \(count) DisplayMesh receivers. Use --host to choose one explicitly."
        case .browserFailed(let detail):
            return "DisplayMesh receiver discovery failed: \(detail)"
        }
    }
}

final class ReceiverDiscovery {
    private let queue = DispatchQueue(
        label: "com.tiburonns.DisplayMesh.macHarness.discovery",
        qos: .userInitiated
    )
    private var browser: NWBrowser?

    func discoverOne(
        timeoutSeconds: TimeInterval =
            ReceiverDiscoveryPolicy
                .defaultTimeoutSeconds
    ) async throws -> NWEndpoint {
        try await withCheckedThrowingContinuation {
            continuation in

            let attempt = ConnectionAttemptGate()
            var latestEndpoints:
                [NWEndpoint] = []

            let browser = NWBrowser(
                for: .bonjour(
                    type:
                        ReceiverDiscoveryPolicy
                            .serviceType,
                    domain: nil
                ),
                using: .tcp
            )

            self.browser = browser

            browser.browseResultsChangedHandler = {
                results, _ in
                latestEndpoints =
                    results
                        .map(\.endpoint)
                        .sorted {
                            String(
                                describing: $0
                            ) <
                            String(
                                describing: $1
                            )
                        }
            }

            browser.stateUpdateHandler = {
                [weak self] state in
                switch state {
                case .failed(let error):
                    guard attempt.claim()
                    else { return }
                    self?.browser?.cancel()
                    self?.browser = nil
                    continuation.resume(
                        throwing:
                            ReceiverDiscoveryError
                                .browserFailed(
                                    error
                                        .localizedDescription
                                )
                    )

                case .cancelled:
                    break

                default:
                    break
                }
            }

            browser.start(queue: queue)

            queue.asyncAfter(
                deadline:
                    .now() +
                    max(timeoutSeconds, 0)
            ) { [weak self] in
                guard attempt.claim()
                else { return }

                self?.browser?.cancel()
                self?.browser = nil

                switch ReceiverDiscoveryPolicy
                    .classify(
                        count:
                            latestEndpoints
                                .count
                    ) {
                case .none:
                    continuation.resume(
                        throwing:
                            ReceiverDiscoveryError
                                .noReceiverFound
                    )

                case .one:
                    continuation.resume(
                        returning:
                            latestEndpoints[0]
                    )

                case .multiple(let count):
                    continuation.resume(
                        throwing:
                            ReceiverDiscoveryError
                                .multipleReceiversFound(
                                    count
                                )
                    )
                }
            }
        }
    }
}
