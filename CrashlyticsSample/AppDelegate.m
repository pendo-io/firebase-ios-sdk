#import "AppDelegate.h"
#import <FirebaseCrashlytics/FIRCrashlytics.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Initialize standalone Crashlytics
    [FIRCrashlytics startWithDeviceID:@"pendo-test-device-id"];
    
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor whiteColor];
    
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor whiteColor];
    
    UIButton *crashButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [crashButton setTitle:@"Trigger Crash" forState:UIControlStateNormal];
    crashButton.frame = CGRectMake(100, 100, 200, 50);
    [crashButton addTarget:self action:@selector(crashButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:crashButton];
    
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)crashButtonTapped {
    NSLog(@"Crashing the app...");
    NSArray *array = @[];
    id object = array[1]; // This will cause an NSRangeException
    NSLog(@"%@", object);
}

@end