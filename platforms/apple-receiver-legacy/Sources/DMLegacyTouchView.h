#import <UIKit/UIKit.h>

@interface DMLegacyTouchView : UIView
@property (nonatomic, copy) void (^onInput)(NSDictionary *event);
@end
