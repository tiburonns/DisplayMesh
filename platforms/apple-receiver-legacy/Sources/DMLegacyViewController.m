#import "DMLegacyViewController.h"
#import "DMLegacyListener.h"
#import "DMLegacyTouchView.h"

@interface DMLegacyViewController () <DMLegacyListenerDelegate>
@property (nonatomic, strong) DMLegacyListener *listener;
@property (nonatomic, strong) UIImageView *videoView;
@property (nonatomic, strong) DMLegacyTouchView *touchView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic) BOOL authorized;
@property (nonatomic) BOOL decodingJPEG;
@property (nonatomic, strong) NSData *pendingJPEG;
@property (nonatomic, strong) dispatch_queue_t decodeQueue;
@end

@implementation DMLegacyViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.decodeQueue = dispatch_queue_create("com.tiburonns.DisplayMesh.legacy.jpeg", DISPATCH_QUEUE_SERIAL);

    self.videoView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    self.videoView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.videoView.contentMode = UIViewContentModeScaleAspectFit;
    self.videoView.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.videoView];

    self.touchView = [[DMLegacyTouchView alloc] initWithFrame:self.view.bounds];
    self.touchView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.touchView];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, self.view.bounds.size.width - 40, 70)];
    self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.statusLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.text = @"Iniciando DisplayMesh Legacy…";
    [self.view addSubview:self.statusLabel];

    __weak typeof(self) weakSelf = self;
    self.touchView.onInput = ^(NSDictionary *event) {
        if (!weakSelf.authorized) { return; }
        NSData *json = [NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
        [weakSelf.listener sendType:DMLegacyMessageTypeInput payload:json];
    };

    self.listener = [[DMLegacyListener alloc] init];
    self.listener.delegate = self;
    NSError *error = nil;
    if (![self.listener start:&error]) {
        self.statusLabel.text = error.localizedDescription;
    } else {
        [UIApplication sharedApplication].idleTimerDisabled = YES;
    }
}

- (void)dealloc {
    [self.listener stop];
    [UIApplication sharedApplication].idleTimerDisabled = NO;
}

- (BOOL)prefersStatusBarHidden { return YES; }

- (void)legacyListener:(DMLegacyListener *)listener didChangeState:(NSString *)state {
    self.statusLabel.text = state;
    if ([state isEqualToString:@"Host desconectado"] || [state isEqualToString:@"Detenido"]) {
        self.authorized = NO;
    }
}

- (void)legacyListener:(DMLegacyListener *)listener didAcceptPeer:(NSString *)peer {
    self.authorized = NO;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Autorizar host"
                                                                   message:[NSString stringWithFormat:@"%@ quiere usar este iPad como pantalla. Acepta solo por USB o en una red de confianza; esta edición heredada no cifra el transporte.", peer]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Rechazar" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [weakSelf.listener disconnectClient];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Autorizar" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        weakSelf.authorized = YES;
        weakSelf.statusLabel.text = @"Host autorizado · perfil JPEG legado";
        [weakSelf sendCapabilitiesAndPanel];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)legacyListener:(DMLegacyListener *)listener didReceiveFrame:(DMLegacyFrame *)frame {
    if (!self.authorized) {
        if (frame.type != DMLegacyMessageTypeHello && frame.type != DMLegacyMessageTypePairing) { return; }
        return;
    }

    if (frame.type == DMLegacyMessageTypeVideo) {
        [self enqueueJPEG:frame.payload];
    }
}

- (void)sendCapabilitiesAndPanel {
    NSDictionary *capabilities = @{
        @"profile": @"legacy-ios9-jpeg",
        @"videoCodecs": @[@"jpeg"],
        @"connectionBindings": @[@"tcp"],
        @"encryption": @[@"none"],
        @"maximumFramesPerSecond": @20,
        @"touch": @YES,
        @"pencil": @NO
    };
    [self.listener sendType:DMLegacyMessageTypeCapabilities
                     payload:[NSJSONSerialization dataWithJSONObject:capabilities options:0 error:nil]];

    UIScreen *screen = [UIScreen mainScreen];
    CGRect nativeBounds = screen.nativeBounds;
    UIDeviceOrientation orientation = [UIDevice currentDevice].orientation;
    NSString *orientationName = UIDeviceOrientationIsLandscape(orientation) ? @"landscape" : @"portrait";
    NSDictionary *panel = @{
        @"pixelWidth": @((NSInteger)nativeBounds.size.width),
        @"pixelHeight": @((NSInteger)nativeBounds.size.height),
        @"nativeScale": @(screen.nativeScale),
        @"maximumFramesPerSecond": @20,
        @"orientation": orientationName,
        @"maximumTouchPoints": @10,
        @"supportsPencil": @NO
    };
    [self.listener sendType:DMLegacyMessageTypePanelDescriptor
                     payload:[NSJSONSerialization dataWithJSONObject:panel options:0 error:nil]];
}

- (void)enqueueJPEG:(NSData *)jpeg {
    self.pendingJPEG = jpeg;
    if (self.decodingJPEG) { return; }
    self.decodingJPEG = YES;
    [self decodeNewestJPEG];
}

- (void)decodeNewestJPEG {
    NSData *jpeg = self.pendingJPEG;
    self.pendingJPEG = nil;
    if (!jpeg) {
        self.decodingJPEG = NO;
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.decodeQueue, ^{
        UIImage *image = [UIImage imageWithData:jpeg scale:[UIScreen mainScreen].scale];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (image) { weakSelf.videoView.image = image; }
            if (weakSelf.pendingJPEG) {
                [weakSelf decodeNewestJPEG];
            } else {
                weakSelf.decodingJPEG = NO;
            }
        });
    });
}

@end
