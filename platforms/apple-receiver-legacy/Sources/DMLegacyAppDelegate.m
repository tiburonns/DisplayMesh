#import "DMLegacyAppDelegate.h"
#import "DMLegacyViewController.h"

@implementation DMLegacyAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[DMLegacyViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
