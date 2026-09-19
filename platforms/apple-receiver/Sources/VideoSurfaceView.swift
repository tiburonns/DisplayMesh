import CoreVideo
import MetalKit
import UIKit

@MainActor
final class VideoSurfaceController {
    private weak var surfaceView: VideoSurfaceView?
    private var latestPixelBuffer: CVPixelBuffer?

    func attach(_ surfaceView: VideoSurfaceView) {
        self.surfaceView = surfaceView
        if let latestPixelBuffer {
            surfaceView.present(latestPixelBuffer)
        }
    }

    func detach(_ surfaceView: VideoSurfaceView) {
        if self.surfaceView === surfaceView {
            self.surfaceView = nil
        }
    }

    func present(_ pixelBuffer: CVPixelBuffer) {
        latestPixelBuffer = pixelBuffer
        surfaceView?.present(pixelBuffer)
    }

    func clear() {
        latestPixelBuffer = nil
        surfaceView?.clearFrame()
    }
}

@MainActor
final class VideoSurfaceView: MTKView {
    private struct MetalState {
        let device: MTLDevice
        let commandQueue: MTLCommandQueue
        let pipelineState: MTLRenderPipelineState
    }

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?
    private var latestPixelBuffer: CVPixelBuffer?

    init(frame: CGRect = .zero) {
        let state = Self.makeMetalState()
        commandQueue = state.commandQueue
        pipelineState = state.pipelineState
        super.init(frame: frame, device: state.device)
        configure(device: state.device)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("VideoSurfaceView must be created programmatically")
    }

    func present(_ pixelBuffer: CVPixelBuffer) {
        latestPixelBuffer = pixelBuffer
        setNeedsDisplay()
    }

    func clearFrame() {
        latestPixelBuffer = nil
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable,
              let renderPassDescriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor =
            MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let pixelBuffer = latestPixelBuffer else {
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        guard CVPixelBufferGetPlaneCount(pixelBuffer) == 2,
              let textureCache
        else {
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var lumaReference: CVMetalTexture?
        var chromaReference: CVMetalTexture?

        let lumaStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .r8Unorm,
            width,
            height,
            0,
            &lumaReference
        )

        let chromaStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .rg8Unorm,
            width / 2,
            height / 2,
            1,
            &chromaReference
        )

        guard lumaStatus == kCVReturnSuccess,
              chromaStatus == kCVReturnSuccess,
              let lumaReference,
              let chromaReference,
              let lumaTexture = CVMetalTextureGetTexture(lumaReference),
              let chromaTexture = CVMetalTextureGetTexture(chromaReference),
              let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
              )
        else {
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        let contentAspect = Float(width) / Float(max(height, 1))
        let viewAspect = Float(drawableSize.width) / Float(max(drawableSize.height, 1))

        let scaleX: Float
        let scaleY: Float

        if contentAspect > viewAspect {
            scaleX = 1
            scaleY = viewAspect / contentAspect
        } else {
            scaleX = contentAspect / viewAspect
            scaleY = 1
        }

        var vertices: [Float] = [
            -scaleX,  scaleY, 0, 0,
            -scaleX, -scaleY, 0, 1,
             scaleX, -scaleY, 1, 1,

            -scaleX,  scaleY, 0, 0,
             scaleX, -scaleY, 1, 1,
             scaleX,  scaleY, 1, 0,
        ]

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(
            &vertices,
            length: MemoryLayout<Float>.stride * vertices.count,
            index: 0
        )
        encoder.setFragmentTexture(lumaTexture, index: 0)
        encoder.setFragmentTexture(chromaTexture, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        commandBuffer.addCompletedHandler { _ in
            _ = pixelBuffer
            _ = lumaReference
            _ = chromaReference
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func configure(device: MTLDevice) {
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
        backgroundColor = .black
        isOpaque = true
        contentMode = .scaleAspectFit

        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &cache
        )

        if status == kCVReturnSuccess {
            textureCache = cache
        }
    }

    private static func makeMetalState() -> MetalState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue()
        else {
            fatalError("DisplayMesh requires Metal")
        }

        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct RasterData {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex RasterData displaymesh_vertex(
            uint vertexID [[vertex_id]],
            constant float4 *vertices [[buffer(0)]]
        ) {
            RasterData out;
            float4 vertex = vertices[vertexID];
            out.position = float4(vertex.xy, 0.0, 1.0);
            out.texCoord = vertex.zw;
            return out;
        }

        fragment float4 displaymesh_fragment(
            RasterData in [[stage_in]],
            texture2d<float, access::sample> luma [[texture(0)]],
            texture2d<float, access::sample> chroma [[texture(1)]]
        ) {
            constexpr sampler linearSampler(
                mag_filter::linear,
                min_filter::linear
            );

            float y = luma.sample(linearSampler, in.texCoord).r;
            float2 uv = chroma.sample(linearSampler, in.texCoord).rg - float2(0.5, 0.5);

            float r = y + 1.5748 * uv.y;
            float g = y - 0.1873 * uv.x - 0.4681 * uv.y;
            float b = y + 1.8556 * uv.x;

            return float4(r, g, b, 1.0);
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "displaymesh_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: "displaymesh_fragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            let pipelineState = try device.makeRenderPipelineState(
                descriptor: descriptor
            )

            return MetalState(
                device: device,
                commandQueue: commandQueue,
                pipelineState: pipelineState
            )
        } catch {
            fatalError("Could not initialize DisplayMesh Metal renderer: \(error)")
        }
    }
}
