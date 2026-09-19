import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import VideoToolbox

struct HostEncoderMetrics {
    var capturedFrames: UInt64 = 0
    var encodedFrames: UInt64 = 0
    var droppedBeforeEncode: UInt64 = 0
    var droppedAfterEncode: UInt64 = 0
    var keyframes: UInt64 = 0
    var megabitsPerSecond: Double = 0
    var framesPerSecond: Double = 0
}

enum HostMediaError: Error, LocalizedError {
    case noDisplays
    case displayNotFound(CGDirectDisplayID)
    case invalidDimensions
    case encoderCreation(OSStatus)
    case encoderConfiguration(CFString, OSStatus)
    case encoderPreparation(OSStatus)
    case encodeSubmission(OSStatus)
    case encodedBufferUnavailable
    case encodedBufferCopy(OSStatus)
    case h264ParameterSets(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noDisplays:
            return "No capturable displays were found"
        case .displayNotFound(let id):
            return "Display ID \(id) is not available to ScreenCaptureKit"
        case .invalidDimensions:
            return "Capture dimensions must be positive and even"
        case .encoderCreation(let status):
            return "VideoToolbox encoder creation failed: \(status)"
        case .encoderConfiguration(let key, let status):
            return "VideoToolbox property \(key) failed: \(status)"
        case .encoderPreparation(let status):
            return "VideoToolbox encoder preparation failed: \(status)"
        case .encodeSubmission(let status):
            return "VideoToolbox rejected a source frame: \(status)"
        case .encodedBufferUnavailable:
            return "The encoded H.264 sample has no data buffer"
        case .encodedBufferCopy(let status):
            return "Could not copy encoded H.264 bytes: \(status)"
        case .h264ParameterSets(let status):
            return "Could not read H.264 SPS/PPS: \(status)"
        }
    }
}

final class DisplayCaptureEncoder: NSObject, SCStreamOutput, SCStreamDelegate {
    var shouldEncodeFrame: (() -> Bool)?
    var onPacket: ((DMPVideoPacket) -> Bool)?
    var onMetrics: ((HostEncoderMetrics) -> Void)?
    var onError: ((String) -> Void)?

    private let queue = DispatchQueue(
        label: "com.tiburonns.DisplayMesh.macHarness.capture",
        qos: .userInteractive
    )

    private var stream: SCStream?
    private var encoder: VTCompressionSession?
    private var frameDuration = CMTime(value: 1, timescale: 60)
    private var encodeInFlight = false
    private var forceNextKeyframe = true
    private var running = false

    private var metrics = HostEncoderMetrics()
    private var metricsWindowStart = ProcessInfo.processInfo.systemUptime
    private var encodedBytesInWindow: UInt64 = 0
    private var encodedFramesInWindow: UInt64 = 0
    private var lastMetricsPublish = ProcessInfo.processInfo.systemUptime

    static func availableDisplays() async throws -> [SCDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        return content.displays
    }

    func start(
        displayID: CGDirectDisplayID?,
        width requestedWidth: Int?,
        height requestedHeight: Int?,
        framesPerSecond: Int,
        bitrateMbps: Int
    ) async throws -> (display: SCDisplay, width: Int, height: Int) {
        guard !running else {
            if let display = try await Self.availableDisplays().first {
                return (display, display.width, display.height)
            }
            throw HostMediaError.noDisplays
        }

        let displays = try await Self.availableDisplays()
        guard !displays.isEmpty else {
            throw HostMediaError.noDisplays
        }

        let display: SCDisplay
        if let displayID {
            guard let requested = displays.first(where: { $0.displayID == displayID }) else {
                throw HostMediaError.displayNotFound(displayID)
            }
            display = requested
        } else {
            display = displays[0]
        }

        let width = makeEven(requestedWidth ?? display.width)
        let height = makeEven(requestedHeight ?? display.height)

        guard width > 0, height > 0, framesPerSecond > 0, bitrateMbps > 0 else {
            throw HostMediaError.invalidDimensions
        }

        try createEncoder(
            width: width,
            height: height,
            framesPerSecond: framesPerSecond,
            bitrateMbps: bitrateMbps
        )

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(framesPerSecond)
        )
        configuration.queueDepth = 3
        configuration.pixelFormat =
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        configuration.capturesAudio = false
        configuration.showsCursor = true

        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        try stream.addStreamOutput(
            self,
            type: .screen,
            sampleHandlerQueue: queue
        )

        self.stream = stream
        frameDuration = configuration.minimumFrameInterval
        running = true

        do {
            try await stream.startCapture()
        } catch {
            running = false
            self.stream = nil
            invalidateEncoder()
            throw error
        }

        return (display, width, height)
    }

    func stop() async {
        guard running else {
            invalidateEncoder()
            return
        }

        running = false

        if let stream {
            try? await stream.stopCapture()
        }

        self.stream = nil

        if let encoder {
            VTCompressionSessionCompleteFrames(
                encoder,
                untilPresentationTimeStamp: .invalid
            )
        }
        invalidateEncoder()
    }

    func requestKeyframe() {
        queue.async { [weak self] in
            self?.forceNextKeyframe = true
        }
    }

    func setBitrate(mbps: Int) {
        guard mbps > 0 else { return }

        queue.async { [weak self] in
            guard let self, let encoder else { return }
            let value = NSNumber(value: mbps * 1_000_000)
            let status = VTSessionSetProperty(
                encoder,
                key: kVTCompressionPropertyKey_AverageBitRate,
                value: value
            )
            if status != noErr {
                publishError(
                    "Could not update encoder bitrate: \(status)"
                )
            }
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              running,
              CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer),
              let imageBuffer = sampleBuffer.imageBuffer
        else {
            return
        }

        metrics.capturedFrames &+= 1

        guard !encodeInFlight,
              shouldEncodeFrame?() ?? true
        else {
            metrics.droppedBeforeEncode &+= 1
            publishMetricsIfNeeded()
            return
        }

        guard let encoder else { return }

        encodeInFlight = true
        let presentationTime = sampleBuffer.presentationTimeStamp.isValid
            ? sampleBuffer.presentationTimeStamp
            : CMClockGetTime(CMClockGetHostTimeClock())

        let frameProperties: CFDictionary?
        if forceNextKeyframe {
            frameProperties = [
                kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue as Any
            ] as CFDictionary
            forceNextKeyframe = false
        } else {
            frameProperties = nil
        }

        var infoFlags = VTEncodeInfoFlags()
        let duration = frameDuration
        let status = VTCompressionSessionEncodeFrame(
            encoder,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTime,
            duration: duration,
            frameProperties: frameProperties,
            infoFlagsOut: &infoFlags
        ) { [weak self] status, infoFlags, encodedSampleBuffer in
            guard let self else { return }

            queue.async {
                self.encodeInFlight = false

                guard status == noErr,
                      !infoFlags.contains(.frameDropped),
                      let encodedSampleBuffer,
                      CMSampleBufferDataIsReady(encodedSampleBuffer)
                else {
                    self.metrics.droppedAfterEncode &+= 1
                    self.forceNextKeyframe = true
                    self.publishMetricsIfNeeded(force: true)
                    return
                }

                do {
                    let packet = try self.makePacket(
                        from: encodedSampleBuffer,
                        fallbackDuration: duration
                    )

                    let accepted = self.onPacket?(packet) ?? true
                    if accepted {
                        self.metrics.encodedFrames &+= 1
                        self.encodedFramesInWindow &+= 1
                        self.encodedBytesInWindow &+= UInt64(packet.annexB.count)
                        if packet.keyframe {
                            self.metrics.keyframes &+= 1
                        }
                    } else {
                        self.metrics.droppedAfterEncode &+= 1
                        self.forceNextKeyframe = true
                    }

                    self.updateWindowMetrics()
                    self.publishMetricsIfNeeded()
                } catch {
                    self.metrics.droppedAfterEncode &+= 1
                    self.forceNextKeyframe = true
                    self.publishError(error.localizedDescription)
                    self.publishMetricsIfNeeded(force: true)
                }
            }
        }

        if status != noErr {
            encodeInFlight = false
            forceNextKeyframe = true
            metrics.droppedAfterEncode &+= 1
            publishError(HostMediaError.encodeSubmission(status).localizedDescription)
            publishMetricsIfNeeded(force: true)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { [weak self] in
            self?.running = false
            self?.publishError(error.localizedDescription)
        }
    }

    private func createEncoder(
        width: Int,
        height: Int,
        framesPerSecond: Int,
        bitrateMbps: Int
    ) throws {
        invalidateEncoder()

        let specification: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder:
                kCFBooleanTrue as Any,
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl:
                kCFBooleanTrue as Any,
        ]

        let imageAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey:
                NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
            kCVPixelBufferWidthKey: NSNumber(value: width),
            kCVPixelBufferHeightKey: NSNumber(value: height),
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]

        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: specification as CFDictionary,
            imageBufferAttributes: imageAttributes as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )

        guard status == noErr, let session else {
            throw HostMediaError.encoderCreation(status)
        }

        encoder = session

        try setProperty(
            kVTCompressionPropertyKey_RealTime,
            value: kCFBooleanTrue
        )
        try setProperty(
            kVTCompressionPropertyKey_AllowFrameReordering,
            value: kCFBooleanFalse
        )
        try setProperty(
            kVTCompressionPropertyKey_MaxFrameDelayCount,
            value: NSNumber(value: 0)
        )
        try setProperty(
            kVTCompressionPropertyKey_ExpectedFrameRate,
            value: NSNumber(value: framesPerSecond)
        )
        try setProperty(
            kVTCompressionPropertyKey_AverageBitRate,
            value: NSNumber(value: bitrateMbps * 1_000_000)
        )
        try setProperty(
            kVTCompressionPropertyKey_MaxKeyFrameInterval,
            value: NSNumber(value: framesPerSecond * 2)
        )
        try setProperty(
            kVTCompressionPropertyKey_ProfileLevel,
            value: kVTProfileLevel_H264_Main_AutoLevel
        )

        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepareStatus == noErr else {
            invalidateEncoder()
            throw HostMediaError.encoderPreparation(prepareStatus)
        }

        forceNextKeyframe = true
        encodeInFlight = false
    }

    private func setProperty(
        _ key: CFString,
        value: CFTypeRef
    ) throws {
        guard let encoder else {
            throw HostMediaError.encoderCreation(-1)
        }

        let status = VTSessionSetProperty(
            encoder,
            key: key,
            value: value
        )
        guard status == noErr else {
            throw HostMediaError.encoderConfiguration(key, status)
        }
    }

    private func makePacket(
        from sampleBuffer: CMSampleBuffer,
        fallbackDuration: CMTime
    ) throws -> DMPVideoPacket {
        guard let blockBuffer = sampleBuffer.dataBuffer else {
            throw HostMediaError.encodedBufferUnavailable
        }

        let keyframe = isKeyframe(sampleBuffer)
        var annexB = Data()

        guard let formatDescription = sampleBuffer.formatDescription else {
            throw HostMediaError.encodedBufferUnavailable
        }

        var parameterSetCount = 0
        var nalUnitHeaderLength: Int32 = 4
        let parameterStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &parameterSetCount,
            nalUnitHeaderLengthOut: &nalUnitHeaderLength
        )

        guard parameterStatus == noErr else {
            throw HostMediaError.h264ParameterSets(parameterStatus)
        }

        if keyframe {
            for index in 0..<parameterSetCount {
                var pointer: UnsafePointer<UInt8>?
                var size = 0
                let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    formatDescription,
                    parameterSetIndex: index,
                    parameterSetPointerOut: &pointer,
                    parameterSetSizeOut: &size,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                )

                guard status == noErr, let pointer, size > 0 else {
                    throw HostMediaError.h264ParameterSets(status)
                }

                let type = pointer.pointee & 0x1f
                if type == 7 || type == 8 {
                    annexB.append(contentsOf: [0, 0, 0, 1])
                    annexB.append(pointer, count: size)
                }
            }
        }

        let totalLength = CMBlockBufferGetDataLength(blockBuffer)
        var avcc = Data(count: totalLength)
        let copyStatus = avcc.withUnsafeMutableBytes { bytes -> OSStatus in
            guard let baseAddress = bytes.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: totalLength,
                destination: baseAddress
            )
        }

        guard copyStatus == noErr else {
            throw HostMediaError.encodedBufferCopy(copyStatus)
        }

        try appendAVCCNALUnits(
            avcc,
            headerLength: Int(nalUnitHeaderLength),
            to: &annexB
        )

        let presentationTime = sampleBuffer.presentationTimeStamp
        let duration = sampleBuffer.duration.isValid
            ? sampleBuffer.duration
            : fallbackDuration

        return DMPVideoPacket(
            presentationTimeMicroseconds: microseconds(presentationTime),
            durationMicroseconds: UInt32(
                min(microseconds(duration), UInt64(UInt32.max))
            ),
            keyframe: keyframe,
            annexB: annexB
        )
    }

    private func appendAVCCNALUnits(
        _ avcc: Data,
        headerLength: Int,
        to annexB: inout Data
    ) throws {
        guard [1, 2, 4].contains(headerLength) else {
            throw DMPProtocolError.malformedVideoPacket
        }

        let bytes = [UInt8](avcc)
        var offset = 0

        while offset + headerLength <= bytes.count {
            var length = 0
            for byte in bytes[offset..<(offset + headerLength)] {
                length = (length << 8) | Int(byte)
            }
            offset += headerLength

            guard length > 0, offset + length <= bytes.count else {
                throw DMPProtocolError.malformedVideoPacket
            }

            annexB.append(contentsOf: [0, 0, 0, 1])
            annexB.append(contentsOf: bytes[offset..<(offset + length)])
            offset += length
        }

        guard offset == bytes.count, !annexB.isEmpty else {
            throw DMPProtocolError.malformedVideoPacket
        }
    }

    private func isKeyframe(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard
            let attachments =
                CMSampleBufferGetSampleAttachmentsArray(
                    sampleBuffer,
                    createIfNecessary: false
                ) as? [[CFString: Any]],
            let first = attachments.first
        else {
            return true
        }

        return !(first[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
    }

    private func microseconds(_ time: CMTime) -> UInt64 {
        guard time.isValid, !time.isIndefinite else { return 0 }
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return UInt64(min(seconds * 1_000_000, Double(UInt64.max)))
    }

    private func updateWindowMetrics() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - metricsWindowStart
        guard elapsed >= 0.5 else { return }

        metrics.framesPerSecond = Double(encodedFramesInWindow) / elapsed
        metrics.megabitsPerSecond =
            Double(encodedBytesInWindow) * 8 / elapsed / 1_000_000

        encodedFramesInWindow = 0
        encodedBytesInWindow = 0
        metricsWindowStart = now
    }

    private func publishMetricsIfNeeded(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastMetricsPublish >= 0.5 else { return }
        lastMetricsPublish = now
        onMetrics?(metrics)
    }

    private func publishError(_ message: String) {
        onError?(message)
    }

    private func invalidateEncoder() {
        if let encoder {
            VTCompressionSessionInvalidate(encoder)
        }
        encoder = nil
        encodeInFlight = false
    }

    private func makeEven(_ value: Int) -> Int {
        value - (value % 2)
    }
}
