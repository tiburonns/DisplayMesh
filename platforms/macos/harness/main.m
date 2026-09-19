#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <signal.h>

static volatile sig_atomic_t gShouldStop = 0;

static void HandleSignal(int signalNumber)
{
    (void)signalNumber;
    gShouldStop = 1;
}

static BOOL ClassAndSelectorsAvailable(Class cls, NSArray<NSString *> *selectors)
{
    if (cls == Nil) {
        return NO;
    }

    for (NSString *selectorName in selectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![cls instancesRespondToSelector:selector] &&
            ![cls respondsToSelector:selector]) {
            return NO;
        }
    }

    return YES;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSUInteger width = 1920;
        NSUInteger height = 1080;
        CGFloat refreshRate = 60.0;
        unsigned int hiDPI = 0;

        if (argc >= 3) {
            width = (NSUInteger)strtoul(argv[1], NULL, 10);
            height = (NSUInteger)strtoul(argv[2], NULL, 10);
        }
        if (argc >= 4) {
            refreshRate = (CGFloat)strtod(argv[3], NULL);
        }
        if (argc >= 5) {
            hiDPI = (unsigned int)strtoul(argv[4], NULL, 10);
        }

        if (width < 640 || height < 480 || refreshRate <= 0.0) {
            fprintf(stderr, "Invalid mode. Usage: %s [width height refreshHz hidpi]\n", argv[0]);
            return 2;
        }

        Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
        Class displayClass = NSClassFromString(@"CGVirtualDisplay");
        Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
        Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");

        BOOL runtimeAvailable =
            ClassAndSelectorsAvailable(descriptorClass, @[@"new"]) &&
            ClassAndSelectorsAvailable(displayClass, @[@"initWithDescriptor:", @"applySettings:", @"displayID"]) &&
            ClassAndSelectorsAvailable(modeClass, @[@"initWithWidth:height:refreshRate:"]) &&
            ClassAndSelectorsAvailable(settingsClass, @[@"new"]);

        if (!runtimeAvailable) {
            fprintf(stderr,
                    "The CGVirtualDisplay runtime is not available on this macOS build.\n"
                    "DisplayMesh did not create a display.\n");
            return 3;
        }

        id descriptor = [descriptorClass new];

        ((void (*)(id, SEL, id))objc_msgSend)(
            descriptor,
            NSSelectorFromString(@"setName:"),
            @"DisplayMesh Virtual Display");

        ((void (*)(id, SEL, unsigned int))objc_msgSend)(
            descriptor,
            NSSelectorFromString(@"setVendorID:"),
            0x444D);

        ((void (*)(id, SEL, unsigned int))objc_msgSend)(
            descriptor,
            NSSelectorFromString(@"setProductID:"),
            0x0001);

        ((void (*)(id, SEL, unsigned int))objc_msgSend)(
            descriptor,
            NSSelectorFromString(@"setSerialNum:"),
            1);

        ((void (*)(id, SEL, unsigned int))objc_msgSend)(
            descriptor,
            NSSelectorFromString(@"setMaxPixelsWide:"),
            (unsigned int)MAX(width, 3840));

        ((void (*)(id, SEL, unsigned int))objc_msgSend)(
            descriptor,
            NSSelectorFromString(@"setMaxPixelsHigh:"),
            (unsigned int)MAX(height, 2160));

        ((void (*)(id, SEL, CGSize))objc_msgSend)(
            descriptor,
            NSSelectorFromString(@"setSizeInMillimeters:"),
            CGSizeMake(600.0, 340.0));

        ((void (*)(id, SEL, id))objc_msgSend)(
            descriptor,
            NSSelectorFromString(@"setQueue:"),
            dispatch_get_main_queue());

        id display = ((id (*)(id, SEL, id))objc_msgSend)(
            [displayClass alloc],
            NSSelectorFromString(@"initWithDescriptor:"),
            descriptor);

        if (display == nil) {
            fprintf(stderr, "CGVirtualDisplay rejected the descriptor.\n");
            return 4;
        }

        id mode = ((id (*)(id, SEL, NSUInteger, NSUInteger, CGFloat))objc_msgSend)(
            [modeClass alloc],
            NSSelectorFromString(@"initWithWidth:height:refreshRate:"),
            width,
            height,
            refreshRate);

        if (mode == nil) {
            fprintf(stderr, "Could not create the requested virtual display mode.\n");
            return 5;
        }

        id settings = [settingsClass new];

        ((void (*)(id, SEL, id))objc_msgSend)(
            settings,
            NSSelectorFromString(@"setModes:"),
            @[mode]);

        ((void (*)(id, SEL, unsigned int))objc_msgSend)(
            settings,
            NSSelectorFromString(@"setHiDPI:"),
            hiDPI);

        BOOL applied = ((BOOL (*)(id, SEL, id))objc_msgSend)(
            display,
            NSSelectorFromString(@"applySettings:"),
            settings);

        if (!applied) {
            fprintf(stderr, "macOS rejected the requested DisplayMesh mode.\n");
            return 6;
        }

        CGDirectDisplayID displayID =
            ((CGDirectDisplayID (*)(id, SEL))objc_msgSend)(
                display,
                NSSelectorFromString(@"displayID"));

        printf(
            "DisplayMesh virtual display created. id=%u mode=%lux%lu@%.2f HiDPI=%u\n",
            displayID,
            (unsigned long)width,
            (unsigned long)height,
            (double)refreshRate,
            hiDPI);

        printf("Press Ctrl+C to remove it.\n");

        signal(SIGINT, HandleSignal);
        signal(SIGTERM, HandleSignal);

        while (!gShouldStop) {
            @autoreleasepool {
                [[NSRunLoop currentRunLoop]
                    runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.20]];
            }
        }

        display = nil;
        settings = nil;
        mode = nil;
        descriptor = nil;

        printf("DisplayMesh virtual display released.\n");
    }

    return 0;
}
