// Copyright 2019 Google
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import <Foundation/Foundation.h>

#import "PNDCrashReporter+Namespace.h"
#import "FIRExceptionModel.h"

#if __has_include(<Crashlytics/Crashlytics.h>)
#warning "FirebaseCrashlytics and Crashlytics are not compatible \
in the same app because including multiple crash reporters can \
cause problems when registering exception handlers."
#endif

NS_ASSUME_NONNULL_BEGIN

/**
 * Delegate protocol to receive parsed crash reports on the next app launch.
 */
@protocol PNDCrashReporterDelegate <NSObject>
@optional
/**
 * Called when a crash report from a previous session has been successfully parsed.
 *
 * The dictionary structure is grouped by the original filename (without the .clsrecord extension).
 *
 * For example:
 * {
 *   "pnd_metadata": {
 *     "identity": { "session_id": "...", "build_version": "..." },
 *     "host": { "os_version": "...", "model": "..." },
 *     "application": { "bundle_id": "..." }
 *   },
 *   "pnd_exception": {
 *     "exception": { "name": "NSRangeException", "reason": "...", "frames": [...] }
 *   },
 *   "pnd_internal_incremental_kv": {
 *     "user-id": "john_doe",
 *     "my-custom-key": "my-custom-value"
 *   }
 * }
 *
 * Note: Hex-encoded fields (like error domains or exception strings) used internally 
 * for async-signal safety are already decoded back to plain text strings in this dictionary.
 */
- (void)crashReporterDidDetectCrashReport:(NSDictionary *)crashReport;
@end

/**
 * The Firebase Crashlytics API provides methods to annotate and manage fatal and
 * non-fatal reports captured and reported to Firebase Crashlytics.
 */
NS_SWIFT_NAME(Crashlytics)
            @interface FIRCrashlytics : NSObject

            /** :nodoc: */
            - (instancetype)init NS_UNAVAILABLE;

            /**
             * The delegate to receive parsed crash reports on the next app launch.
             */
            @property(nonatomic, weak, readonly) id<PNDCrashReporterDelegate> delegate;

/**
 * Initializes and accesses the singleton PendoCrashReporter instance and sets the delegate for Phase 2.
 *
 * @param delegate The delegate to receive parsed crash reports.
 * @param debugMode If YES, internal debug logs will be printed to the console.
 * @return The singleton Crashlytics instance.
 */
+ (instancetype)startMonitoringWithDelegate:(nullable id<PNDCrashReporterDelegate>)delegate
                                  debugMode:(BOOL)debugMode
    NS_SWIFT_NAME(startMonitoring(delegate:debugMode:));

/**
 * Accesses the singleton Crashlytics instance.
 *
 * @return The singleton Crashlytics instance.
 */
+ (instancetype)crashlytics NS_SWIFT_NAME(crashlytics());

/**
 * Updates the custom data (e.g. userId, accountId, sessionId) to be safely saved with the crash report.
 * This directly writes to the underlying async-signal-safe KV storage.
 *
 * @param customData A dictionary of string keys to string values.
 */
+ (void)updateCustomData:(NSDictionary<NSString *, NSString *> *)customData;

/**
 * Records a non-fatal event described by an Error object.
 *
 * @param error Non-fatal error to be recorded
 */
- (void)recordError:(NSError *)error NS_SWIFT_NAME(record(error:));

/**
 * Records a non-fatal event described by an NSError object.
 *
 * @param error Non-fatal error to be recorded
 * @param userInfo Additional keys and values to send with the logged error.
 */
- (void)recordError:(NSError *)error
           userInfo:(nullable NSDictionary<NSString *, id> *)userInfo
    NS_SWIFT_NAME(record(error:userInfo:));

/**
 * Records an Exception Model described by an ExceptionModel object.
 *
 * @param exceptionModel Instance of the ExceptionModel to be recorded
 */
- (void)recordExceptionModel:(FIRExceptionModel *)exceptionModel
    NS_SWIFT_NAME(record(exceptionModel:));

/**
 * Returns whether the app crashed during the previous execution.
 */
- (BOOL)didCrashDuringPreviousExecution;

@end

NS_ASSUME_NONNULL_END
