#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CrashHelpers : NSObject

+ (void)throwCPPException;
+ (void)callTerminate;

@end

NS_ASSUME_NONNULL_END
