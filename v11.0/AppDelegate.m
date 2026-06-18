#import "AppDelegate.h"
#import "GameViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];
    GameViewController *gvc = [[GameViewController alloc] init];
    self.window.rootViewController = gvc;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
