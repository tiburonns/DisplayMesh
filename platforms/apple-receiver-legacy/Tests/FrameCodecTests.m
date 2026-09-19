#import <Foundation/Foundation.h>
#import "DMLegacyFrameCodec.h"

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        NSData *payload = [@"legacy-frame" dataUsingEncoding:NSUTF8StringEncoding];
        NSData *encoded = [DMLegacyFrameCodec encodeType:DMLegacyMessageTypeTelemetry
                                                   flags:0x0102
                                                sequence:42
                                                 payload:payload];
        Require(encoded.length == 16 + payload.length, @"encoded size");

        DMLegacyFrameCodec *codec = [[DMLegacyFrameCodec alloc] init];
        [codec appendData:[encoded subdataWithRange:NSMakeRange(0, 8)]];
        Require([codec nextFrameWithError:nil] == nil, @"fragmented header must wait");
        [codec appendData:[encoded subdataWithRange:NSMakeRange(8, encoded.length - 8)]];

        NSError *error = nil;
        DMLegacyFrame *decoded = [codec nextFrameWithError:&error];
        Require(error == nil, @"valid frame error");
        Require(decoded.type == DMLegacyMessageTypeTelemetry, @"message type");
        Require(decoded.flags == 0x0102, @"flags");
        Require(decoded.sequence == 42, @"sequence");
        Require([decoded.payload isEqualToData:payload], @"payload");

        NSMutableData *invalid = [encoded mutableCopy];
        uint8_t byte = 'X';
        [invalid replaceBytesInRange:NSMakeRange(0, 1) withBytes:&byte];
        [codec reset];
        [codec appendData:invalid];
        error = nil;
        Require([codec nextFrameWithError:&error] == nil, @"invalid frame rejected");
        Require(error != nil, @"invalid frame reports error");

        NSLog(@"PASS: legacy DMP frame codec");
    }
    return 0;
}
