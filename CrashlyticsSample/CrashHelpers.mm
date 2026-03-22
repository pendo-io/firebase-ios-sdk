#import "CrashHelpers.h"
#include <stdexcept>
#include <exception>

@implementation CrashHelpers

+ (void)throwCPPException {
    throw std::runtime_error("This is a C++ exception thrown intentionally for testing.");
}

+ (void)callTerminate {
    std::terminate();
}

@end
