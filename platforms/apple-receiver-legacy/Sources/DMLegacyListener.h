#import <Foundation/Foundation.h>
#import "DMLegacyFrameCodec.h"

@class DMLegacyListener;

@protocol DMLegacyListenerDelegate <NSObject>
- (void)legacyListener:(DMLegacyListener *)listener didChangeState:(NSString *)state;
- (void)legacyListener:(DMLegacyListener *)listener didReceiveFrame:(DMLegacyFrame *)frame;
- (void)legacyListener:(DMLegacyListener *)listener didAcceptPeer:(NSString *)peer;
@end

@interface DMLegacyListener : NSObject
@property (nonatomic, weak) id<DMLegacyListenerDelegate> delegate;
- (BOOL)start:(NSError **)error;
- (void)stop;
- (void)disconnectClient;
- (void)sendType:(DMLegacyMessageType)type payload:(NSData *)payload;
@end
