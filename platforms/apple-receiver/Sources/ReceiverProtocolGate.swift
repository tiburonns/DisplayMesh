import Foundation

enum ReceiverProtocolGate {
    static func permits(
        _ type: DMPMessageType,
        authorized: Bool
    ) -> Bool {
        if authorized {
            switch type {
            case .video, .capabilities, .error:
                return true
            case .hello, .panelDescriptor, .pairing, .input,
                 .telemetry, .keyframeRequest:
                return false
            }
        }

        return type == .pairing
    }
}
