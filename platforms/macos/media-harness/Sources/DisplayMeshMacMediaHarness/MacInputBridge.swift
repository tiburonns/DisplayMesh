import ApplicationServices
import CoreGraphics
import Foundation

enum MacPointerAction: Equatable {
    case move(CGPoint)
    case down(CGPoint)
    case drag(CGPoint)
    case up(CGPoint)
    case scroll(horizontal: Int32, vertical: Int32)
}

struct MacGestureMapper {
    private var contacts: [UInt32: CGPoint] = [:]
    private var draggingContactID: UInt32?
    private var scrollMode = false
    private var lastScrollCentroid: CGPoint?

    mutating func apply(
        _ sample: DMPInputSample,
        targetBounds: CGRect
    ) -> [MacPointerAction] {
        let point = sample.normalizedPoint

        if sample.phase == .hover,
           sample.kind == .pencil,
           contacts.isEmpty {
            return [.move(map(point, to: targetBounds))]
        }

        switch sample.phase {
        case .began:
            contacts[sample.contactID] = point

            if contacts.count == 1, !scrollMode {
                draggingContactID = sample.contactID
                let mapped = map(point, to: targetBounds)
                return [.move(mapped), .down(mapped)]
            }

            if contacts.count >= 2 {
                var actions: [MacPointerAction] = []

                if let draggingContactID,
                   let draggingPoint = contacts[draggingContactID] {
                    actions.append(
                        .up(map(draggingPoint, to: targetBounds))
                    )
                }

                self.draggingContactID = nil
                scrollMode = true
                lastScrollCentroid = centroid()
                return actions
            }

            return []

        case .moved:
            guard contacts[sample.contactID] != nil else {
                return []
            }

            contacts[sample.contactID] = point

            if scrollMode {
                guard contacts.count >= 2 else {
                    return []
                }

                let currentCentroid = centroid()
                defer { lastScrollCentroid = currentCentroid }

                guard let previous = lastScrollCentroid,
                      let currentCentroid else {
                    return []
                }

                let deltaX = currentCentroid.x - previous.x
                let deltaY = currentCentroid.y - previous.y

                let horizontal = scrollUnits(deltaX)
                let vertical = scrollUnits(deltaY)

                if horizontal == 0 && vertical == 0 {
                    return []
                }

                return [
                    .scroll(
                        horizontal: horizontal,
                        vertical: vertical
                    )
                ]
            }

            if draggingContactID == sample.contactID {
                return [.drag(map(point, to: targetBounds))]
            }

            return []

        case .ended, .cancelled:
            guard contacts[sample.contactID] != nil else {
                return []
            }

            contacts[sample.contactID] = point
            var actions: [MacPointerAction] = []

            if draggingContactID == sample.contactID {
                actions.append(.up(map(point, to: targetBounds)))
                draggingContactID = nil
            }

            contacts.removeValue(forKey: sample.contactID)

            if scrollMode {
                if contacts.count >= 2 {
                    lastScrollCentroid = centroid()
                } else if contacts.isEmpty {
                    scrollMode = false
                    lastScrollCentroid = nil
                } else {
                    // Keep scroll mode suspended until every finger is up.
                    // This avoids turning the remaining finger into an
                    // unexpected click/drag in the middle of a gesture.
                    lastScrollCentroid = nil
                }
            }

            return actions

        case .hover:
            return []
        }
    }

    mutating func reset(
        targetBounds: CGRect
    ) -> [MacPointerAction] {
        var actions: [MacPointerAction] = []

        if let draggingContactID,
           let point = contacts[draggingContactID] {
            actions.append(.up(map(point, to: targetBounds)))
        }

        contacts.removeAll()
        draggingContactID = nil
        scrollMode = false
        lastScrollCentroid = nil
        return actions
    }

    private func map(
        _ normalized: CGPoint,
        to bounds: CGRect
    ) -> CGPoint {
        CGPoint(
            x: bounds.minX + normalized.x * max(bounds.width - 1, 0),
            y: bounds.minY + normalized.y * max(bounds.height - 1, 0)
        )
    }

    private func centroid() -> CGPoint? {
        guard !contacts.isEmpty else { return nil }

        var x: CGFloat = 0
        var y: CGFloat = 0

        for point in contacts.values {
            x += point.x
            y += point.y
        }

        let count = CGFloat(contacts.count)
        return CGPoint(x: x / count, y: y / count)
    }

    private func scrollUnits(_ normalizedDelta: CGFloat) -> Int32 {
        // Apple documents scroll wheel values as small signed integers.
        // Scale normalized finger motion into that range and clamp it so
        // a delayed sample cannot create an extreme scroll jump.
        let scaled = Int(
            (normalizedDelta * 120).rounded()
        )
        return Int32(max(-10, min(10, scaled)))
    }
}

final class MacInputBridge {
    var onError: ((String) -> Void)?

    private let queue = DispatchQueue(
        label: "com.tiburonns.DisplayMesh.macHarness.input",
        qos: .userInteractive
    )

    private let targetBounds: CGRect
    private let eventSource: CGEventSource?
    private var mapper = MacGestureMapper()
    private var reportedPermissionError = false

    init(targetBounds: CGRect) {
        self.targetBounds = targetBounds
        self.eventSource = CGEventSource(stateID: .hidSystemState)
    }

    @discardableResult
    func requestAccessibilityIfNeeded() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let promptKey =
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func handle(_ payload: Data) {
        do {
            let sample = try DMPInputSample.decode(payload)

            queue.async { [weak self] in
                guard let self else { return }

                guard AXIsProcessTrusted() else {
                    reportPermissionErrorOnce()
                    return
                }

                reportedPermissionError = false
                let actions = mapper.apply(
                    sample,
                    targetBounds: targetBounds
                )
                actions.forEach(post)
            }
        } catch {
            onError?(error.localizedDescription)
        }
    }

    func reset() {
        queue.async { [weak self] in
            guard let self else { return }
            let actions = mapper.reset(targetBounds: targetBounds)
            actions.forEach(post)
        }
    }

    private func post(_ action: MacPointerAction) {
        switch action {
        case .move(let point):
            postMouse(type: .mouseMoved, point: point)

        case .down(let point):
            postMouse(type: .leftMouseDown, point: point)

        case .drag(let point):
            postMouse(type: .leftMouseDragged, point: point)

        case .up(let point):
            postMouse(type: .leftMouseUp, point: point)

        case .scroll(let horizontal, let vertical):
            guard let event = CGEvent(
                scrollWheelEvent2Source: eventSource,
                units: .pixel,
                wheelCount: 2,
                wheel1: -vertical,
                wheel2: -horizontal,
                wheel3: 0
            ) else {
                onError?("Could not create macOS scroll event")
                return
            }
            event.post(tap: .cghidEventTap)
        }
    }

    private func postMouse(
        type: CGEventType,
        point: CGPoint
    ) {
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            onError?("Could not create macOS pointer event")
            return
        }

        event.post(tap: .cghidEventTap)
    }

    private func reportPermissionErrorOnce() {
        guard !reportedPermissionError else { return }
        reportedPermissionError = true
        onError?(
            "Accessibility permission is required for iPhone/iPad touch control. " +
            "Enable it for the harness/Terminal in System Settings, then try again."
        )
    }
}
