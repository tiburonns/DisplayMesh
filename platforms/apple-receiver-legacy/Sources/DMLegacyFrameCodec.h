#import <Foundation/Foundation.h>

typedef NS_ENUM(uint8_t, DMLegacyMessageType) {
    DMLegacyMessageTypeHello = 0x01,
    DMLegacyMessageTypeCapabilities = 0x02,
    DMLegacyMessageTypePanelDescriptor = 0x03,
    DMLegacyMessageTypePairing = 0x04,
    DMLegacyMessageTypeVideo = 0x10,
    DMLegacyMessageTypeInput = 0x20,
    DMLegacyMessageTypeTelemetry = 0x30,
    DMLegacyMessageTypeKeyframeRequest = 0x31,
    DMLegacyMessageTypeError = 0x7f
};

@interface DMLegacyFrame : NSObject
@property (nonatomic) DMLegacyMessageType type;
@property (nonatomic) uint16_t flags;
@property (nonatomic) uint32_t sequence;
@property (nonatomic, strong) NSData *payload;
@end

@interface DMLegacyFrameCodec : NSObject
- (void)appendData:(NSData *)data;
- (DMLegacyFrame *)nextFrameWithError:(NSError **)error;
- (void)reset;
+ (NSData *)encodeType:(DMLegacyMessageType)type
                 flags:(uint16_t)flags
              sequence:(uint32_t)sequence
               payload:(NSData *)payload;
@end
