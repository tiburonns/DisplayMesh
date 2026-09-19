import Combine
import Foundation
import UIKit

@MainActor
final class ReceiverViewModel: ObservableObject {
    @Published private(set) var listenerState: ReceiverListenerState = .stopped
    @Published private(set) var panelDescriptor: PanelDescriptor?
    @Published private(set) var capturedInputSamples: UInt64 = 0
    @Published private(set) var sessionAuthorized = false
    @Published private(set) var pendingPairing: PairingRequest?
    @Published private(set) var lastProtocolError: String?
    @Published var diagnosticsEnabled = false

    private let listener: ReceiverListener

    init(listener: ReceiverListener = ReceiverListener()) {
        self.listener = listener

        listener.onState = { [weak self] state in
            guard let self else { return }
            listenerState = state

            switch state {
            case .connected:
                sessionAuthorized = false
                pendingPairing = nil
                lastProtocolError = nil
            case .stopped, .failed:
                resetAuthorization()
            default:
                break
            }
        }

        listener.onFrame = { [weak self] frame in
            self?.handle(frame)
        }
    }

    var isListening: Bool {
        switch listenerState {
        case .stopped, .failed: return false
        case .starting, .ready, .waiting, .connected: return true
        }
    }

    func startReceiver() {
        guard !isListening else { return }

        do {
            try listener.start()
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            listenerState = .failed(error.localizedDescription)
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    func stopReceiver() {
        listener.stop()
        listenerState = .stopped
        resetAuthorization()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func updatePanelDescriptor(_ descriptor: PanelDescriptor) {
        guard panelDescriptor != descriptor else { return }
        panelDescriptor = descriptor
        sendPanelDescriptorIfAuthorized()
    }

    func captureInput(_ event: ReceiverInputEvent) {
        capturedInputSamples &+= 1
        guard sessionAuthorized,
              let payload = try? JSONEncoder().encode(event) else { return }

        listener.send(type: .input, payload: payload)
    }

    func acceptPairing() {
        guard let request = pendingPairing, request.isValid else {
            lastProtocolError = "Invalid pairing request"
            pendingPairing = nil
            sessionAuthorized = false
            return
        }

        sessionAuthorized = true
        pendingPairing = nil
        sendPairingResponse(accepted: true)
        sendPanelDescriptorIfAuthorized()
    }

    func rejectPairing() {
        sessionAuthorized = false
        pendingPairing = nil
        sendPairingResponse(accepted: false)
    }

    private func handle(_ frame: DMPFrame) {
        switch frame.type {
        case .hello:
            resetAuthorization()

        case .pairing:
            do {
                let request = try JSONDecoder().decode(PairingRequest.self, from: frame.payload)
                guard request.isValid else {
                    throw PairingValidationError.invalidRequest
                }
                pendingPairing = request
                sessionAuthorized = false
                lastProtocolError = nil
            } catch {
                pendingPairing = nil
                sessionAuthorized = false
                lastProtocolError = error.localizedDescription
            }

        case .video:
            guard sessionAuthorized else {
                lastProtocolError = "Rejected video before pairing authorization"
                return
            }
            // Video decode/presentation is the next media-path milestone.

        case .capabilities, .panelDescriptor, .input, .telemetry, .keyframeRequest, .error:
            break
        }
    }

    private func sendPairingResponse(accepted: Bool) {
        let response = PairingResponse(
            accepted: accepted,
            receiverName: UIDevice.current.name,
            protocolVersion: Int(DMPFrame.version)
        )

        guard let payload = try? JSONEncoder().encode(response) else { return }
        listener.send(type: .pairing, payload: payload)
    }

    private func sendPanelDescriptorIfAuthorized() {
        guard sessionAuthorized,
              let panelDescriptor,
              let payload = try? JSONEncoder().encode(panelDescriptor) else { return }

        listener.send(type: .panelDescriptor, payload: payload)
    }

    private func resetAuthorization() {
        sessionAuthorized = false
        pendingPairing = nil
    }
}

private enum PairingValidationError: LocalizedError {
    case invalidRequest

    var errorDescription: String? {
        "Invalid DisplayMesh pairing request"
    }
}
