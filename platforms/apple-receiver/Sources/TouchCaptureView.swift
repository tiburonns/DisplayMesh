import UIKit

@MainActor
final class TouchCaptureView: UIView {
    var onInput: ((ReceiverInputEvent) -> Void)?
    var onPanelDescriptor: ((PanelDescriptor) -> Void)?

    private var contactIDs: [ObjectIdentifier: UInt32] = [:]
    private var nextContactID: UInt32 = 1
    private var lastPanelDescriptor: PanelDescriptor?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        publishPanelDescriptorIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        publishPanelDescriptorIfNeeded()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        emit(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let samples = event?.coalescedTouches(for: touch) ?? [touch]
            for sample in samples {
                emit(sample)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        emit(touches)
        removeContactIDs(for: touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        emit(touches)
        removeContactIDs(for: touches)
    }

    private func configure() {
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        isOpaque = false
        backgroundColor = .clear
    }

    private func publishPanelDescriptorIfNeeded() {
        guard window != nil else { return }
        let descriptor = PanelDescriptor.current(for: self)
        guard descriptor != lastPanelDescriptor else { return }
        lastPanelDescriptor = descriptor
        onPanelDescriptor?(descriptor)
    }

    private func emit(_ touches: Set<UITouch>) {
        for touch in touches {
            emit(touch)
        }
    }

    private func emit(_ touch: UITouch) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let key = ObjectIdentifier(touch)
        let contactID = contactIDs[key] ?? allocateContactID(for: key)
        let location = touch.location(in: self)

        let x = min(max(location.x / bounds.width, 0), 1)
        let y = min(max(location.y / bounds.height, 0), 1)

        let phase: ReceiverInputEvent.Phase
        switch touch.phase {
        case .began, .regionEntered:
            phase = .began
        case .moved, .stationary, .regionMoved:
            phase = .moved
        case .ended, .regionExited:
            phase = .ended
        case .cancelled:
            phase = .cancelled
        @unknown default:
            phase = .cancelled
        }

        let pencil: ReceiverInputEvent.PencilData?
        if touch.type == .pencil {
            let pressure: CGFloat
            if touch.maximumPossibleForce > 0 {
                pressure = min(max(touch.force / touch.maximumPossibleForce, 0), 1)
            } else {
                pressure = 0
            }

            pencil = ReceiverInputEvent.PencilData(
                pressure: Double(pressure),
                altitude: Double(touch.altitudeAngle),
                azimuth: Double(touch.azimuthAngle(in: self))
            )
        } else {
            pencil = nil
        }

        onInput?(
            ReceiverInputEvent(
                contactID: contactID,
                phase: phase,
                normalizedX: Double(x),
                normalizedY: Double(y),
                timestamp: touch.timestamp,
                pencil: pencil
            )
        )
    }

    private func allocateContactID(for key: ObjectIdentifier) -> UInt32 {
        let id = nextContactID
        nextContactID &+= 1
        contactIDs[key] = id
        return id
    }

    private func removeContactIDs(for touches: Set<UITouch>) {
        for touch in touches {
            contactIDs.removeValue(forKey: ObjectIdentifier(touch))
        }
    }
}
