import UIKit

struct PanelDescriptor: Codable, Equatable {
    enum Orientation: String, Codable {
        case portrait
        case landscape
        case unknown
    }

    let pixelWidth: Int
    let pixelHeight: Int
    let nativeScale: Double
    let maximumFramesPerSecond: Int
    let orientation: Orientation
    let maximumTouchPoints: Int
    let supportsPencil: Bool

    @MainActor
    static func current(for view: UIView) -> PanelDescriptor {
        let screen = view.window?.windowScene?.screen ?? UIScreen.main
        let nativeBounds = screen.nativeBounds
        let interfaceOrientation = view.window?.windowScene?.interfaceOrientation

        let orientation: Orientation
        switch interfaceOrientation {
        case .portrait, .portraitUpsideDown:
            orientation = .portrait
        case .landscapeLeft, .landscapeRight:
            orientation = .landscape
        default:
            orientation = .unknown
        }

        return PanelDescriptor(
            pixelWidth: Int(nativeBounds.width.rounded()),
            pixelHeight: Int(nativeBounds.height.rounded()),
            nativeScale: Double(screen.nativeScale),
            maximumFramesPerSecond: screen.maximumFramesPerSecond,
            orientation: orientation,
            maximumTouchPoints: 10,
            supportsPencil: UIDevice.current.userInterfaceIdiom == .pad
        )
    }
}
