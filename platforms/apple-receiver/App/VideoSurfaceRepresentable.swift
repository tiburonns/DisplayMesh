import SwiftUI

struct VideoSurfaceRepresentable: UIViewRepresentable {
    let controller: VideoSurfaceController

    func makeUIView(context: Context) -> VideoSurfaceView {
        let view = VideoSurfaceView()
        controller.attach(view)
        return view
    }

    func updateUIView(_ uiView: VideoSurfaceView, context: Context) {}

    static func dismantleUIView(
        _ uiView: VideoSurfaceView,
        coordinator: Void
    ) {
        uiView.clearFrame()
    }
}
