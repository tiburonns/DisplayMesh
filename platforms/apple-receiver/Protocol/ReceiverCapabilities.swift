import Foundation

struct ReceiverCapabilities: Codable, Equatable {
    static let schemaVersion = 1
    static let h264 = "h264"
    static let tcp = "tcp"
    static let touch = "touch"
    static let pencil = "pencil"

    let schemaVersion: Int
    let protocolVersion: Int
    let codecs: [String]
    let connectionBindings: [String]
    let inputKinds: [String]
    let telemetrySupported: Bool
    let maximumVideoPayloadBytes: Int
    let encryptedTransport: Bool

    var isValid: Bool {
        schemaVersion == Self.schemaVersion
            && protocolVersion == Int(DMPFrame.version)
            && !codecs.isEmpty
            && codecs.count <= 8
            && connectionBindings.count <= 8
            && inputKinds.count <= 8
            && Set(codecs).count == codecs.count
            && Set(connectionBindings).count == connectionBindings.count
            && Set(inputKinds).count == inputKinds.count
            && (1...DMPFrame.maximumPayloadSize)
                .contains(maximumVideoPayloadBytes)
    }

    var supportsDevelopmentHost: Bool {
        isValid
            && codecs.contains(Self.h264)
            && connectionBindings.contains(Self.tcp)
            && encryptedTransport
    }

    static func development(
        panel: PanelDescriptor?
    ) -> ReceiverCapabilities {
        var inputKinds = [Self.touch]
        if panel?.supportsPencil == true {
            inputKinds.append(Self.pencil)
        }

        return ReceiverCapabilities(
            schemaVersion: Self.schemaVersion,
            protocolVersion: Int(DMPFrame.version),
            codecs: [Self.h264],
            connectionBindings: [Self.tcp],
            inputKinds: inputKinds,
            telemetrySupported: true,
            maximumVideoPayloadBytes: DMPFrame.maximumPayloadSize,
            encryptedTransport: true
        )
    }
}
