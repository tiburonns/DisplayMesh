#import "DMLegacyTouchView.h"

@interface DMLegacyTouchView ()
@property (nonatomic, strong) NSMapTable *contactIDs;
@property (nonatomic) uint32_t nextContactID;
@end

@implementation DMLegacyTouchView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.multipleTouchEnabled = YES;
        self.exclusiveTouch = NO;
        self.backgroundColor = [UIColor clearColor];
        _contactIDs = [NSMapTable weakToStrongObjectsMapTable];
        _nextContactID = 1;
    }
    return self;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event { [self emitTouches:touches phase:@"began" remove:NO]; }
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event { [self emitTouches:touches phase:@"moved" remove:NO]; }
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event { [self emitTouches:touches phase:@"ended" remove:YES]; }
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event { [self emitTouches:touches phase:@"cancelled" remove:YES]; }

- (void)emitTouches:(NSSet *)touches phase:(NSString *)phase remove:(BOOL)remove {
    for (UITouch *touch in touches) {
        NSNumber *contact = [self.contactIDs objectForKey:touch];
        if (!contact) {
            contact = @(self.nextContactID++);
            [self.contactIDs setObject:contact forKey:touch];
        }
        CGPoint point = [touch locationInView:self];
        double x = self.bounds.size.width > 0 ? point.x / self.bounds.size.width : 0;
        double y = self.bounds.size.height > 0 ? point.y / self.bounds.size.height : 0;
        NSDictionary *payload = @{
            @"contactID": contact,
            @"phase": phase,
            @"normalizedX": @(MAX(0.0, MIN(1.0, x))),
            @"normalizedY": @(MAX(0.0, MIN(1.0, y))),
            @"timestamp": @(touch.timestamp),
            @"pencil": [NSNull null]
        };
        if (self.onInput) { self.onInput(payload); }
        if (remove) { [self.contactIDs removeObjectForKey:touch]; }
    }
}

@end
