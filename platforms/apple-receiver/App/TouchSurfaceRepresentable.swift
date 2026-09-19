import SwiftUI

struct TouchSurfaceRepresentable: UIViewRepresentable {
    let onInput: (ReceiverInputEvent) -> Void
    let onPanelDescriptor: (PanelDescriptor) -> Void

    func makeUIView(context: Context) -> TouchCaptureView {
        let view = TouchCaptureView(frame: .zero)
        configure(view)
        return view
    }

    func updateUIView(_ uiView: TouchCaptureView, context: Context) {
        configure(uiView)
    }

    private func configure(_ view: TouchCaptureView) {
        view.onInput = onInput
        view.onPanelDescriptor = onPanelDescriptor
    }
}
