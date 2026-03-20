#import "AppDelegate.h"
#import <FirebaseCrashlytics/FIRCrashlytics.h>
#import "CrashHelpers.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Initialize standalone Crashlytics
    [FIRCrashlytics startMonitoringWithDelegate:nil];
    
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor whiteColor];
    
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor groupTableViewBackgroundColor]; // Light gray background
    
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:vc.view.bounds];
    scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:scrollView];
    
    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 16; // reduced spacing to fit more
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:stackView];
    
    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor constant:40],
        [stackView.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor constant:-40],
        [stackView.leadingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.leadingAnchor constant:20],
        [stackView.trailingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.trailingAnchor constant:-20]
    ]];
    
    UILabel *headerLabel = [[UILabel alloc] init];
    headerLabel.text = @"Crash Testing App";
    headerLabel.font = [UIFont boldSystemFontOfSize:28];
    headerLabel.textAlignment = NSTextAlignmentCenter;
    [stackView addArrangedSubview:headerLabel];
    
    [self addCrashButtonToStack:stackView
                          title:@"1. NSRangeException (Out of Bounds)"
                    description:@"Cause: Accessing an array index that is out of bounds.\nCaught by: NSException handler (FIRCLSException)."
                         action:@selector(triggerNSRangeException)];
                         
    [self addCrashButtonToStack:stackView
                          title:@"2. Unrecognized Selector"
                    description:@"Cause: Calling a method that does not exist on an object.\nCaught by: NSException handler (FIRCLSException)."
                         action:@selector(triggerUnrecognizedSelector)];
                         
    [self addCrashButtonToStack:stackView
                          title:@"3. NSInternalInconsistencyException"
                    description:@"Cause: NSAssert failure (e.g., failed internal validation).\nCaught by: NSException handler (FIRCLSException)."
                         action:@selector(triggerAssertionFailure)];
                         
    [self addCrashButtonToStack:stackView
                          title:@"4. C++ std::runtime_error"
                    description:@"Cause: Throwing a C++ exception without a catch block.\nCaught by: C++ terminate handler (FIRCLSException)."
                         action:@selector(triggerCPPException)];
                         
    [self addCrashButtonToStack:stackView
                          title:@"5. EXC_BAD_ACCESS (NULL Pointer)"
                    description:@"Cause: Dereferencing a NULL or invalid pointer.\nCaught by: Mach Exception (EXC_BAD_ACCESS) or POSIX (SIGSEGV)."
                         action:@selector(triggerBadAccess)];
                         
    [self addCrashButtonToStack:stackView
                          title:@"6. SIGBUS (Read-Only Memory)"
                    description:@"Cause: Writing to read-only memory (string literal).\nCaught by: Mach Exception (EXC_BAD_ACCESS) or POSIX (SIGBUS)."
                         action:@selector(triggerSigBus)];
                         
    [self addCrashButtonToStack:stackView
                          title:@"7. SIGABRT (Abort)"
                    description:@"Cause: Calling abort() directly or failed system assertions.\nCaught by: POSIX Signal handler (SIGABRT)."
                         action:@selector(triggerSigAbort)];
                         
    [self addCrashButtonToStack:stackView
                          title:@"8. SIGILL (Illegal Instruction)"
                    description:@"Cause: CPU cannot execute the instruction (__builtin_trap()).\nCaught by: Mach Exception (EXC_BAD_INSTRUCTION) or POSIX (SIGILL)."
                         action:@selector(triggerSigIll)];
                         
    [self addCrashButtonToStack:stackView
                          title:@"9. SIGFPE (Floating Point)"
                    description:@"Cause: Erroneous arithmetic operation (sent via raise()).\nCaught by: Mach Exception (EXC_ARITHMETIC) or POSIX (SIGFPE)."
                         action:@selector(triggerSigFPE)];
                         
    [self addCrashButtonToStack:stackView
                          title:@"10. Stack Overflow"
                    description:@"Cause: Infinite recursion exhausting stack memory.\nCaught by: Mach Exception or POSIX Signal handler (SIGSEGV)."
                         action:@selector(triggerStackOverflow)];
                         
    [self addCrashButtonToStack:stackView
                          title:@"11. Use After Free (Dangling Ptr)"
                    description:@"Cause: Writing to memory that has already been freed.\nCaught by: Mach Exception (EXC_BAD_ACCESS) or POSIX (SIGSEGV)."
                         action:@selector(triggerUseAfterFree)];
                         
    [self addCrashButtonToStack:stackView
                          title:@"12. Background Thread Crash"
                    description:@"Cause: NULL pointer deref on a background GCD queue.\nCaught by: Mach Exception. Shows thread state capture."
                         action:@selector(triggerBackgroundThreadCrash)];
    
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)addCrashButtonToStack:(UIStackView *)stackView title:(NSString *)title description:(NSString *)description action:(SEL)action {
    UIView *container = [[UIView alloc] init];
    container.backgroundColor = [UIColor whiteColor];
    container.layer.cornerRadius = 8;
    container.layer.masksToBounds = YES;
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:button];
    
    UILabel *label = [[UILabel alloc] init];
    label.text = description;
    label.numberOfLines = 0;
    label.font = [UIFont systemFontOfSize:13];
    label.textColor = [UIColor darkGrayColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];
    
    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [button.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [button.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        
        [label.topAnchor constraintEqualToAnchor:button.bottomAnchor constant:8],
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-16]
    ]];
    
    [stackView addArrangedSubview:container];
}

#pragma mark - Crash Triggers

- (void)triggerNSRangeException {
    NSLog(@"Triggering NSRangeException...");
    NSArray *array = @[];
    id object = array[1];
    NSLog(@"%@", object); // Should never reach here
}

- (void)triggerUnrecognizedSelector {
    NSLog(@"Triggering Unrecognized Selector...");
    id string = @"A string";
    [string performSelector:@selector(thisMethodDoesNotExist)];
}

- (void)triggerAssertionFailure {
    NSLog(@"Triggering NSInternalInconsistencyException via NSAssert...");
    NSAssert(NO, @"This is an intentional assertion failure.");
}

- (void)triggerCPPException {
    NSLog(@"Triggering C++ std::runtime_error...");
    [CrashHelpers throwCPPException];
}

- (void)triggerBadAccess {
    NSLog(@"Triggering EXC_BAD_ACCESS (NULL Pointer)...");
    int *pointer = NULL;
    *pointer = 42; 
}

- (void)triggerSigBus {
    NSLog(@"Triggering SIGBUS (Write to read-only string literal)...");
    char *str = (char *)"readonly";
    str[0] = 'w';
}

- (void)triggerSigAbort {
    NSLog(@"Triggering SIGABRT...");
    abort();
}

- (void)triggerSigIll {
    NSLog(@"Triggering SIGILL...");
    __builtin_trap();
}

- (void)triggerSigFPE {
    NSLog(@"Triggering SIGFPE...");
    raise(SIGFPE);
}

- (void)triggerStackOverflow {
    NSLog(@"Triggering Stack Overflow...");
    [self triggerStackOverflow];
}

- (void)triggerUseAfterFree {
    NSLog(@"Triggering Use After Free...");
    void *ptr = malloc(16);
    free(ptr);
    // Writing to freed memory; might cause EXC_BAD_ACCESS depending on allocator state
    memset(ptr, 0x42, 16); 
}

- (void)triggerBackgroundThreadCrash {
    NSLog(@"Triggering crash on background thread...");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int *pointer = NULL;
        *pointer = 42;
    });
}

@end