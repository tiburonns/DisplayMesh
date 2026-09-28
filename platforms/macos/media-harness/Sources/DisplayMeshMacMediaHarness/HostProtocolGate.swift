enum HostReceiverPhase: Equatable {
    case awaitingHello
    case readyToPair
    case awaitingPairingResponse
    case awaitingPanel
    case streaming
}

enum HostProtocolGate {
    static func permits(
        _ type: DMPMessageType,
        phase: HostReceiverPhase
    ) -> Bool {
        if type == .error {
            return true
        }

        switch phase {
        case .awaitingHello:
            return type == .hello

        case .readyToPair:
            return false

        case .awaitingPairingResponse:
            return type == .pairing

        case .awaitingPanel:
            switch type {
            case .panelDescriptor, .capabilities, .keyframeRequest,
                 .input, .telemetry:
                return true
            default:
                return false
            }

        case .streaming:
            switch type {
            case .panelDescriptor, .capabilities, .keyframeRequest,
                 .input, .telemetry:
                return true
            default:
                return false
            }
        }
    }
}
