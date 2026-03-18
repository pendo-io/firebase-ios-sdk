#import "CrashHelpers.h"
#include <stdexcept>

@implementation CrashHelpers

+ (void)throwCPPException {
    throw std::runtime_error("This is a C++ exception thrown intentionally for testing.");
}

@end
