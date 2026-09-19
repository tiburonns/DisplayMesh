import Combine
import Foundation
import UIKit

@MainActor
final class ReceiverViewModel: ObservableObject {
    @Published private(set) var listenerState: ReceiverListenerState = .stopped
    @Published private(set) var panelDescriptor: PanelDescriptor?
    @Published private(set) var capturedInputSamples: UInt64 = 0
    @Published private(set) var sessionAuthorized = false
    @Published var diagnosticsEnabled = false

    private let listener: ReceiverListener

    init(listener: ReceiverListener = ReceiverListener()) {
        self.listener = listener

        listener.onState = { [weak self] state in
            self?.listenerState = state
            switch state {
            case .connected, .stopped, .failed:
                self?.sessionAuthorized = false
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
        sessionAuthorized = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func updatePanelDescriptor(_ descriptor: PanelDescriptor) {
        guard panelDescriptor != descriptor else { return }
        panelDescriptor = descriptor
        guard sessionAuthorized,
              let payload = try? JSONEncoder().encode(descriptor) else { return }
        listener.send(type: .panelDescriptor, payload: payload)
    }

    func captureInput(_ event: ReceiverInputEvent) {
        capturedInputSamples &+= 1
        guard sessionAuthorized,
              let payload = try? JSONEncoder().encode(event) else { return }
        listener.send(type: .input, payload: payload)
    }

    private func handle(_ frame: DMPFrame) {
        switch frame.type {
        case .hello, .pairing:
            sessionAuthorized = false
        default:
            break
        }
    }
}
