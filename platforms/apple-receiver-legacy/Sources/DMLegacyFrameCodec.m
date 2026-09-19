#import "DMLegacyFrameCodec.h"

enum { DMPHeaderSize = 16 };
static const NSUInteger DMPMaximumPayloadSize = 16 * 1024 * 1024;
static NSString * const DMPErrorDomain = @"com.tiburonns.DisplayMesh.Legacy.Frame";

@implementation DMLegacyFrame
@end

@interface DMLegacyFrameCodec ()
@property (nonatomic, strong) NSMutableData *buffer;
@end

@implementation DMLegacyFrameCodec

- (instancetype)init {
    self = [super init];
    if (self) { _buffer = [NSMutableData data]; }
    return self;
}

- (void)appendData:(NSData *)data {
    if (data.length > 0) { [self.buffer appendData:data]; }
}

- (void)reset {
    [self.buffer setLength:0];
}

- (DMLegacyFrame *)nextFrameWithError:(NSError **)error {
    if (self.buffer.length < DMPHeaderSize) { return nil; }

    const uint8_t *bytes = self.buffer.bytes;
    if (bytes[0] != 'D' || bytes[1] != 'M' || bytes[2] != 'P' || bytes[3] != '1') {
        if (error) { *error = [NSError errorWithDomain:DMPErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Cabecera DMP inválida"}]; }
        return nil;
    }
    if (bytes[4] != 1) {
        if (error) { *error = [NSError errorWithDomain:DMPErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"Versión DMP no compatible"}]; }
        return nil;
    }
    switch (bytes[5]) {
        case DMLegacyMessageTypeHello:
        case DMLegacyMessageTypeCapabilities:
        case DMLegacyMessageTypePanelDescriptor:
        case DMLegacyMessageTypePairing:
        case DMLegacyMessageTypeVideo:
        case DMLegacyMessageTypeInput:
        case DMLegacyMessageTypeTelemetry:
        case DMLegacyMessageTypeKeyframeRequest:
        case DMLegacyMessageTypeError:
            break;
        default:
            if (error) { *error = [NSError errorWithDomain:DMPErrorDomain code:4 userInfo:@{NSLocalizedDescriptionKey: @"Tipo de mensaje DMP no compatible"}]; }
            return nil;
    }

    uint32_t payloadLength = ((uint32_t)bytes[12] << 24) |
                             ((uint32_t)bytes[13] << 16) |
                             ((uint32_t)bytes[14] << 8) |
                             (uint32_t)bytes[15];
    if (payloadLength > DMPMaximumPayloadSize) {
        if (error) { *error = [NSError errorWithDomain:DMPErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey: @"Payload DMP demasiado grande"}]; }
        return nil;
    }

    NSUInteger totalLength = DMPHeaderSize + (NSUInteger)payloadLength;
    if (self.buffer.length < totalLength) { return nil; }

    DMLegacyFrame *frame = [[DMLegacyFrame alloc] init];
    frame.type = (DMLegacyMessageType)bytes[5];
    frame.flags = ((uint16_t)bytes[6] << 8) | (uint16_t)bytes[7];
    frame.sequence = ((uint32_t)bytes[8] << 24) |
                     ((uint32_t)bytes[9] << 16) |
                     ((uint32_t)bytes[10] << 8) |
                     (uint32_t)bytes[11];
    frame.payload = [self.buffer subdataWithRange:NSMakeRange(DMPHeaderSize, payloadLength)];
    [self.buffer replaceBytesInRange:NSMakeRange(0, totalLength) withBytes:NULL length:0];
    return frame;
}

+ (NSData *)encodeType:(DMLegacyMessageType)type
                 flags:(uint16_t)flags
              sequence:(uint32_t)sequence
               payload:(NSData *)payload {
    NSData *body = payload ?: [NSData data];
    if (body.length > DMPMaximumPayloadSize) { return nil; }

    uint8_t header[DMPHeaderSize] = { 'D', 'M', 'P', '1', 1, (uint8_t)type };
    header[6] = (uint8_t)(flags >> 8);
    header[7] = (uint8_t)flags;
    header[8] = (uint8_t)(sequence >> 24);
    header[9] = (uint8_t)(sequence >> 16);
    header[10] = (uint8_t)(sequence >> 8);
    header[11] = (uint8_t)sequence;
    uint32_t length = (uint32_t)body.length;
    header[12] = (uint8_t)(length >> 24);
    header[13] = (uint8_t)(length >> 16);
    header[14] = (uint8_t)(length >> 8);
    header[15] = (uint8_t)length;

    NSMutableData *encoded = [NSMutableData dataWithBytes:header length:DMPHeaderSize];
    [encoded appendData:body];
    return encoded;
}

@end
