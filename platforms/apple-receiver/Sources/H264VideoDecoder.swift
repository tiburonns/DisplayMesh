import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

struct ReceiverVideoMetrics: Equatable {
    var receivedFrames: UInt64 = 0
    var decodedFrames: UInt64 = 0
    var droppedFrames: UInt64 = 0
    var framesPerSecond: Double = 0
    var megabitsPerSecond: Double = 0
    var averageDecodeMilliseconds: Double = 0
    var hardwareAccelerated: Bool?
    var lastSequence: UInt32?
    var decodeQueueDepth: Int = 0
    var presentationQueueDepth: Int = 0
}

final class H264VideoDecoder {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    var onMetrics: ((ReceiverVideoMetrics) -> Void)?
    var onNeedsKeyframe: (() -> Void)?
    var onError: ((String) -> Void)?

    private let queue = DispatchQueue(
        label: "com.tiburonns.DisplayMesh.receiver.h264",
        qos: .userInteractive
    )

    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private var sequenceParameterSet: Data?
    private var pictureParameterSet: Data?

    private var waitingForKeyframe = true
    private var generation: UInt64 = 0
    private var inFlightFrames = 0
    private let maximumInFlightFrames = 3

    private struct PendingPresentation {
        let imageBuffer: CVPixelBuffer
        let timestamp: CMTime
    }

    private var presentationGate = LatestFramePresentationGate()
    private var pendingPresentation: PendingPresentation?

    private var metrics = ReceiverVideoMetrics()
    private var metricsWindowStart = ProcessInfo.processInfo.systemUptime
    private var decodedInWindow: UInt64 = 0
    private var bytesInWindow: UInt64 = 0
    private var lastMetricsPublish = ProcessInfo.processInfo.systemUptime

    func submit(_ packet: DMPVideoPacket, sequence: UInt32) {
        queue.async { [weak self] in
            self?.submitLocked(packet, sequence: sequence)
        }
    }

    func reset() {
        queue.async { [weak self] in
            self?.resetLocked(clearParameterSets: true)
        }
    }

    private func submitLocked(_ packet: DMPVideoPacket, sequence: UInt32) {
        metrics.receivedFrames &+= 1
        metrics.lastSequence = sequence
        bytesInWindow &+= UInt64(packet.bitstream.count)

        guard packet.codec == .h264 else {
            dropLocked(reason: "Receiver only supports H.264 in the current media milestone")
            return
        }

        let nalUnits = splitAnnexB(packet.bitstream)
        guard !nalUnits.isEmpty else {
            dropLocked(reason: "H.264 access unit did not contain Annex-B NAL units")
            return
        }

        var parameterSetsChanged = false
        var mediaNALUnits: [Data] = []
        var containsIDR = false

        for nal in nalUnits {
            guard let firstByte = nal.first else { continue }
            let nalType = firstByte & 0x1f

            switch nalType {
            case 7:
                if sequenceParameterSet != nal {
                    sequenceParameterSet = nal
                    parameterSetsChanged = true
                }
            case 8:
                if pictureParameterSet != nal {
                    pictureParameterSet = nal
                    parameterSetsChanged = true
                }
            case 9:
                break
            default:
                if nalType == 5 {
                    containsIDR = true
                }
                mediaNALUnits.append(nal)
            }
        }

        if parameterSetsChanged {
            do {
                try rebuildFormatDescriptionLocked()
            } catch {
                dropLocked(reason: error.localizedDescription)
                return
            }
        }

        let isKeyframe = packet.isKeyframe || containsIDR

        if waitingForKeyframe && !isKeyframe {
            metrics.droppedFrames &+= 1
            publishMetricsLocked()
            return
        }

        guard !mediaNALUnits.isEmpty else {
            publishMetricsLocked()
            return
        }

        guard formatDescription != nil else {
            waitingForKeyframe = true
            metrics.droppedFrames &+= 1
            requestKeyframeLocked()
            publishMetricsLocked()
            return
        }

        if inFlightFrames >= maximumInFlightFrames {
            metrics.droppedFrames &+= 1
            publishMetricsLocked(force: true)
            invalidateSessionLocked()
            waitingForKeyframe = true
            requestKeyframeLocked()
            publishMetricsLocked(force: true)
            return
        }

        do {
            try ensureSessionLocked()

            if isKeyframe {
                waitingForKeyframe = false
            }

            let sampleBuffer = try makeSampleBuffer(
                nalUnits: mediaNALUnits,
                presentationTimeMicroseconds: packet.presentationTimeMicroseconds,
                durationMicroseconds: packet.durationMicroseconds
            )

            try decodeLocked(
                sampleBuffer,
                sequence: sequence,
                presentationTimeMicroseconds: packet.presentationTimeMicroseconds
            )
        } catch {
            dropLocked(reason: error.localizedDescription)
        }
    }

    private func decodeLocked(
        _ sampleBuffer: CMSampleBuffer,
        sequence: UInt32,
        presentationTimeMicroseconds: UInt64
    ) throws {
        guard let session else {
            throw H264DecoderError.sessionUnavailable
        }

        let submittedAt = DispatchTime.now().uptimeNanoseconds
        let decodeGeneration = generation
        inFlightFrames += 1

        var infoFlags = VTDecodeInfoFlags(rawValue: 0)
        let status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: VTDecodeFrameFlags(rawValue: 1 << 0),
            infoFlagsOut: &infoFlags
        ) { [weak self] status, infoFlags, imageBuffer, presentationTimeStamp, _ in
            guard let self else { return }

            queue.async {
                guard decodeGeneration == self.generation else { return }

                self.inFlightFrames = max(0, self.inFlightFrames - 1)

                if status != noErr {
                    self.metrics.droppedFrames &+= 1
                    self.waitingForKeyframe = true
                    self.invalidateSessionLocked()
                    self.requestKeyframeLocked()
                    self.publishError("VideoToolbox decode failed with status \(status)")
                    self.publishMetricsLocked(force: true)
                    return
                }

                if infoFlags.rawValue & (1 << 1) != 0 || imageBuffer == nil {
                    self.metrics.droppedFrames &+= 1
                    self.publishMetricsLocked()
                    return
                }

                guard let imageBuffer else { return }

                let decodeMilliseconds =
                    Double(DispatchTime.now().uptimeNanoseconds - submittedAt) / 1_000_000
                self.metrics.averageDecodeMilliseconds =
                    self.metrics.averageDecodeMilliseconds == 0
                    ? decodeMilliseconds
                    : (self.metrics.averageDecodeMilliseconds * 0.9) + (decodeMilliseconds * 0.1)

                self.metrics.decodedFrames &+= 1
                self.metrics.lastSequence = sequence
                self.decodedInWindow &+= 1
                self.updateHardwareAccelerationLocked()
                self.updateWindowMetricsLocked()
                self.publishMetricsLocked()

                let timestamp = presentationTimeStamp.isValid
                    ? presentationTimeStamp
                    : CMTime(
                        value: Int64(clamping: presentationTimeMicroseconds),
                        timescale: 1_000_000
                    )

                self.enqueuePresentationLocked(
                    imageBuffer,
                    timestamp: timestamp
                )
            }
        }

        if status != noErr {
            inFlightFrames = max(0, inFlightFrames - 1)
            throw H264DecoderError.decodeSubmissionFailed(status)
        }
    }

    private func ensureSessionLocked() throws {
        if session != nil {
            return
        }

        guard let formatDescription else {
            throw H264DecoderError.missingFormatDescription
        }

        let decoderSpecification: [CFString: Any] = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true
        ]

        let imageBufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey:
                Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]

        var newSession: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: decoderSpecification as CFDictionary,
            imageBufferAttributes: imageBufferAttributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &newSession
        )

        guard status == noErr, let newSession else {
            throw H264DecoderError.sessionCreationFailed(status)
        }

        VTSessionSetProperty(
            newSession,
            key: kVTDecompressionPropertyKey_RealTime,
            value: kCFBooleanTrue
        )

        session = newSession
        updateHardwareAccelerationLocked()
    }

    private func rebuildFormatDescriptionLocked() throws {
        guard let sequenceParameterSet, let pictureParameterSet else {
            return
        }

        var newDescription: CMFormatDescription?
        var creationStatus: OSStatus = -1

        sequenceParameterSet.withUnsafeBytes { spsBytes in
            pictureParameterSet.withUnsafeBytes { ppsBytes in
                guard
                    let spsBase = spsBytes.bindMemory(to: UInt8.self).baseAddress,
                    let ppsBase = ppsBytes.bindMemory(to: UInt8.self).baseAddress
                else {
                    return
                }

                let pointers = [spsBase, ppsBase]
                let sizes = [sequenceParameterSet.count, pictureParameterSet.count]

                creationStatus = pointers.withUnsafeBufferPointer { pointerBuffer in
                    sizes.withUnsafeBufferPointer { sizeBuffer in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: pointerBuffer.baseAddress!,
                            parameterSetSizes: sizeBuffer.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &newDescription
                        )
                    }
                }
            }
        }

        guard creationStatus == noErr, let newDescription else {
            throw H264DecoderError.formatDescriptionFailed(creationStatus)
        }

        formatDescription = newDescription
        invalidateSessionLocked()
        waitingForKeyframe = true
    }

    private func makeSampleBuffer(
        nalUnits: [Data],
        presentationTimeMicroseconds: UInt64,
        durationMicroseconds: UInt32
    ) throws -> CMSampleBuffer {
        guard let formatDescription else {
            throw H264DecoderError.missingFormatDescription
        }

        var avcc = Data()
        for nal in nalUnits where !nal.isEmpty {
            var length = UInt32(nal.count).bigEndian
            Swift.withUnsafeBytes(of: &length) {
                avcc.append(contentsOf: $0)
            }
            avcc.append(nal)
        }

        guard !avcc.isEmpty else {
            throw H264DecoderError.emptyAccessUnit
        }

        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avcc.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avcc.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == kCMBlockBufferNoErr, let blockBuffer else {
            throw H264DecoderError.blockBufferFailed(status)
        }

        status = avcc.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return OSStatus(-1)
            }

            return CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: avcc.count
            )
        }

        guard status == kCMBlockBufferNoErr else {
            throw H264DecoderError.blockBufferFailed(status)
        }

        let presentationTime = CMTime(
            value: Int64(clamping: presentationTimeMicroseconds),
            timescale: 1_000_000
        )
        let duration = durationMicroseconds == 0
            ? CMTime.invalid
            : CMTime(value: Int64(durationMicroseconds), timescale: 1_000_000)

        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleSize = avcc.count
        var sampleBuffer: CMSampleBuffer?

        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let sampleBuffer else {
            throw H264DecoderError.sampleBufferFailed(status)
        }

        return sampleBuffer
    }

    private func splitAnnexB(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return [] }

        var starts: [(index: Int, length: Int)] = []
        var index = 0

        while index + 3 <= bytes.count {
            if index + 4 <= bytes.count,
               bytes[index] == 0,
               bytes[index + 1] == 0,
               bytes[index + 2] == 0,
               bytes[index + 3] == 1 {
                starts.append((index, 4))
                index += 4
                continue
            }

            if bytes[index] == 0,
               bytes[index + 1] == 0,
               bytes[index + 2] == 1 {
                starts.append((index, 3))
                index += 3
                continue
            }

            index += 1
        }

        guard !starts.isEmpty else { return [] }

        var result: [Data] = []
        for position in starts.indices {
            let start = starts[position].index + starts[position].length
            let end = position + 1 < starts.count
                ? starts[position + 1].index
                : bytes.count

            guard start < end else { continue }
            result.append(Data(bytes[start..<end]))
        }

        return result
    }

    private func dropLocked(reason: String) {
        metrics.droppedFrames &+= 1
        waitingForKeyframe = true
        requestKeyframeLocked()
        publishError(reason)
        publishMetricsLocked(force: true)
    }

    private func enqueuePresentationLocked(
        _ imageBuffer: CVPixelBuffer,
        timestamp: CMTime
    ) {
        let decision = presentationGate.enqueue()

        if decision.replacedPendingFrame {
            metrics.droppedFrames &+= 1
            publishMetricsLocked()
        }

        pendingPresentation = PendingPresentation(
            imageBuffer: imageBuffer,
            timestamp: timestamp
        )

        guard decision.shouldScheduleDrain else {
            return
        }

        schedulePresentationDrainLocked()
    }

    private func schedulePresentationDrainLocked() {
        DispatchQueue.main.async { [weak self] in
            self?.drainLatestPresentationOnMain()
        }
    }

    private func drainLatestPresentationOnMain() {
        let presentation: PendingPresentation? = queue.sync {
            guard presentationGate.takePending() else {
                return nil
            }

            let latest = pendingPresentation
            pendingPresentation = nil
            return latest
        }

        if let presentation {
            onFrame?(
                presentation.imageBuffer,
                presentation.timestamp
            )
        }

        queue.async { [weak self] in
            guard let self else { return }

            if self.presentationGate.completePresentation() {
                self.schedulePresentationDrainLocked()
            }
        }
    }

    private func requestKeyframeLocked() {
        DispatchQueue.main.async { [weak self] in
            self?.onNeedsKeyframe?()
        }
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(message)
        }
    }

    private func updateHardwareAccelerationLocked() {
        guard let session else {
            metrics.hardwareAccelerated = nil
            return
        }

        var value: CFTypeRef?
        let status = VTSessionCopyProperty(
            session,
            key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
            allocator: kCFAllocatorDefault,
            valueOut: &value
        )

        if status == noErr, let number = value as? NSNumber {
            metrics.hardwareAccelerated = number.boolValue
        }
    }

    private func updateWindowMetricsLocked() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - metricsWindowStart

        guard elapsed >= 0.5 else { return }

        metrics.framesPerSecond = Double(decodedInWindow) / elapsed
        metrics.megabitsPerSecond = (Double(bytesInWindow) * 8) / elapsed / 1_000_000
        decodedInWindow = 0
        bytesInWindow = 0
        metricsWindowStart = now
    }

    private func publishMetricsLocked(force: Bool = false) {
        metrics.decodeQueueDepth = inFlightFrames
        metrics.presentationQueueDepth =
            presentationGate.hasPendingFrame ? 1 : 0

        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastMetricsPublish >= 0.25 else { return }
        lastMetricsPublish = now
        let snapshot = metrics

        DispatchQueue.main.async { [weak self] in
            self?.onMetrics?(snapshot)
        }
    }

    private func invalidateSessionLocked() {
        generation &+= 1
        inFlightFrames = 0

        if let session {
            VTDecompressionSessionInvalidate(session)
        }

        session = nil
        metrics.hardwareAccelerated = nil
        pendingPresentation = nil
        presentationGate.reset()
    }

    private func resetLocked(clearParameterSets: Bool) {
        invalidateSessionLocked()
        waitingForKeyframe = true

        if clearParameterSets {
            formatDescription = nil
            sequenceParameterSet = nil
            pictureParameterSet = nil
        }

        metrics = ReceiverVideoMetrics()
        decodedInWindow = 0
        bytesInWindow = 0
        metricsWindowStart = ProcessInfo.processInfo.systemUptime
        publishMetricsLocked(force: true)
    }
}

private enum H264DecoderError: LocalizedError {
    case missingFormatDescription
    case sessionUnavailable
    case sessionCreationFailed(OSStatus)
    case formatDescriptionFailed(OSStatus)
    case blockBufferFailed(OSStatus)
    case sampleBufferFailed(OSStatus)
    case decodeSubmissionFailed(OSStatus)
    case emptyAccessUnit

    var errorDescription: String? {
        switch self {
        case .missingFormatDescription:
            return "H.264 SPS/PPS have not been received yet"
        case .sessionUnavailable:
            return "VideoToolbox decoder session is unavailable"
        case .sessionCreationFailed(let status):
            return "Could not create VideoToolbox decoder: \(status)"
        case .formatDescriptionFailed(let status):
            return "Could not create H.264 format description: \(status)"
        case .blockBufferFailed(let status):
            return "Could not create compressed video buffer: \(status)"
        case .sampleBufferFailed(let status):
            return "Could not create H.264 sample buffer: \(status)"
        case .decodeSubmissionFailed(let status):
            return "VideoToolbox rejected a frame: \(status)"
        case .emptyAccessUnit:
            return "H.264 access unit is empty"
        }
    }
}
