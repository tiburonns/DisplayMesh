import Foundation

enum ReceiverProtocolGate {
    static func permits(
        _ type: DMPMessageType,
        authorized: Bool
    ) -> Bool {
        if authorized {
            switch type {
            case .video, .error:
                return true
            case .hello, .capabilities, .panelDescriptor, .pairing,
                 .input, .telemetry, .keyframeRequest:
                return false
            }
        }

        return type == .pairing
    }
}
