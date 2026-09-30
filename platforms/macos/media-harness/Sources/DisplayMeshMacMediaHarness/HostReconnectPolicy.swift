import Foundation
import Network

enum HostReconnectPolicy {
    static let defaultMaximumRetries = 3
    static let maximumSupportedRetries = 10
    static let baseDelaySeconds: TimeInterval = 0.5
    static let maximumDelaySeconds: TimeInterval = 4
    static let sessionPollNanoseconds: UInt64 = 250_000_000

    static func shouldRetry(
        _ error: Error,
        completedRetries: Int,
        maximumRetries: Int
    ) -> Bool {
        guard completedRetries >= 0,
              maximumRetries > 0,
              completedRetries < maximumRetries else {
            return false
        }

        return isRetryable(error)
    }

    static func isRetryable(_ error: Error) -> Bool {
        if error is NWError {
            return true
        }

        guard let protocolError = error as? DMPProtocolError else {
            return false
        }

        switch protocolError {
        case .connectionClosed:
            return true
        case .timeout(let operation):
            return operation == "transport connection"
                || operation == "receiver hello challenge"
                || operation == "receiver capabilities"
                || operation == "receiver panel descriptor"
        case .invalidMagic,
             .unsupportedVersion,
             .unsupportedMessageType,
             .payloadTooLarge,
             .payloadTooLargeForMessage,
             .invalidPayloadLength,
             .malformedVideoPacket,
             .pairingRejected,
             .unexpectedSequence,
             .invalidReceiverHello,
             .invalidReceiverTelemetry,
             .invalidReceiverCapabilities,
             .incompatibleReceiverCapabilities,
             .invalidPanelDescriptor,
             .invalidPairingResponse,
             .invalidSessionPhase,
             .invalidPairingRequest:
            return false
        }
    }

    static func delaySeconds(
        forRetryNumber retryNumber: Int
    ) -> TimeInterval {
        guard retryNumber > 0 else {
            return 0
        }

        let exponent = min(retryNumber - 1, 16)
        let delay =
            baseDelaySeconds * pow(2, Double(exponent))

        return min(delay, maximumDelaySeconds)
    }
}
