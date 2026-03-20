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

#include <stdatomic.h>


#include "Crashlytics/Crashlytics/Components/FIRCLSCrashedMarkerFile.h"
#include "Crashlytics/Crashlytics/Components/FIRCLSGlobals.h"
#import "Crashlytics/Crashlytics/Components/FIRCLSHost.h"
#include "Crashlytics/Crashlytics/Components/FIRCLSUserLogging.h"
#import "Crashlytics/Crashlytics/DataCollection/FIRCLSDataCollectionToken.h"
#include "Crashlytics/Crashlytics/Handlers/FIRCLSException.h"
#import "Crashlytics/Crashlytics/Helpers/FIRCLSDefines.h"
#include "Crashlytics/Crashlytics/Helpers/FIRCLSUtility.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSExecutionIdentifierModel.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSFileManager.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSSettings.h"

#import "Crashlytics/Crashlytics/Helpers/FIRCLSLogger.h"
#import "Crashlytics/Shared/FIRCLSByteUtility.h"
#import "Crashlytics/Shared/FIRCLSConstants.h"
#import "Crashlytics/Shared/FIRCLSFABHost.h"

#import "Crashlytics/Crashlytics/Controllers/FIRCLSContextManager.h"
#import "Crashlytics/Crashlytics/Controllers/FIRCLSExistingReportManager.h"
#import "Crashlytics/Crashlytics/Controllers/FIRCLSManagerData.h"
#import "Crashlytics/Crashlytics/Controllers/FIRCLSNotificationManager.h"
#import "Crashlytics/Crashlytics/Controllers/FIRCLSReportManager.h"
#import "Crashlytics/Crashlytics/Controllers/FIRCLSReportUploader.h"
#import "Crashlytics/Crashlytics/Private/FIRCLSExistingReportManager_Private.h"
#import "Crashlytics/Crashlytics/Private/FIRCLSOnDemandModel_Private.h"
#import "Crashlytics/Crashlytics/Private/FIRExceptionModel_Private.h"



#if SWIFT_PACKAGE
@import FirebaseCrashlyticsSwift;
#elif __has_include(<FirebaseCrashlytics/FirebaseCrashlytics-Swift.h>)
#import <FirebaseCrashlytics/FirebaseCrashlytics-Swift.h>
#elif __has_include("FirebaseCrashlytics-Swift.h")
// If frameworks are not available, fall back to importing the header as it
// should be findable from a header search path pointing to the build
// directory. See #12611 for more context.
#import "FirebaseCrashlytics-Swift.h"
#endif

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

FIRCLSContext _firclsContext;
dispatch_queue_t _firclsLoggingQueue;
dispatch_queue_t _firclsBinaryImageQueue;
dispatch_queue_t _firclsExceptionQueue;

static atomic_bool _hasInitializedInstance;


@interface FIRCrashlytics ()

@property(nonatomic) BOOL didPreviouslyCrash;
@property(nonatomic) FIRCLSFileManager *fileManager;
@property(nonatomic, weak) id<PNDCrashReporterDelegate> delegate;

@property(nonatomic) FIRCLSReportManager *reportManager;

@property(nonatomic) FIRCLSReportUploader *reportUploader;

@property(nonatomic, strong) FIRCLSExistingReportManager *existingReportManager;

// Dependencies common to each of the Controllers
@property(nonatomic, strong) FIRCLSManagerData *managerData;

@property(nonatomic) BOOL isContextInitialized;

@end

@implementation FIRCrashlytics

static FIRCrashlytics *sharedInstance = nil;

#pragma mark - Singleton Support

- (instancetype)init {
  self = [super init];

  if (self) {
    bool expectedCalled = NO;
    if (!atomic_compare_exchange_strong(&_hasInitializedInstance, &expectedCalled, YES)) {
      FIRCLSErrorLog(@"Cannot instantiate more than one instance of PendoCrashReporter.");
      return nil;
    }

    NSLog(@"[PendoCrashReporter] Version %@", FIRCLSSDKVersion());

    FIRCLSDeveloperLog("PendoCrashReporter", @"Running on %@, %@ (%@)", FIRCLSHostModelInfo(),
                       FIRCLSHostOSDisplayVersion(), FIRCLSHostOSBuildVersion());

    _fileManager = [[FIRCLSFileManager alloc] init];

    FIRCLSSettings *settings = [[FIRCLSSettings alloc] init];

    FIRCLSOnDemandModel *onDemandModel =
        [[FIRCLSOnDemandModel alloc] initWithFIRCLSSettings:settings fileManager:_fileManager];
    _managerData = [[FIRCLSManagerData alloc] initWithFileManager:_fileManager
                                                         settings:settings
                                                    onDemandModel:onDemandModel];

    _reportUploader = [[FIRCLSReportUploader alloc] initWithManagerData:_managerData];

    _existingReportManager =
        [[FIRCLSExistingReportManager alloc] initWithManagerData:_managerData
                                                  reportUploader:_reportUploader];

    _reportManager = [[FIRCLSReportManager alloc] initWithManagerData:_managerData
                                                existingReportManager:_existingReportManager];

    _didPreviouslyCrash = [_fileManager didCrashOnPreviousExecution];
    // Process did crash during previous execution
    if (_didPreviouslyCrash) {
      // Delete the crash file marker in the background ensure start up is as fast as possible
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSString *crashedMarkerFileFullPath = [[self.fileManager rootPath]
            stringByAppendingPathComponent:[NSString
                                               stringWithUTF8String:FIRCLSCrashedMarkerFileName]];
        [self.fileManager removeItemAtPath:crashedMarkerFileFullPath];
      });
    }

    _isContextInitialized = [_reportManager startWithProfiling];
    if (!_isContextInitialized) {
      FIRCLSErrorLog(@"Crash reporting could not be initialized");
    }
  }
  return self;
}

+ (instancetype)startMonitoringWithDelegate:(id<PNDCrashReporterDelegate>)delegate {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[FIRCrashlytics alloc] init];
    sharedInstance.delegate = delegate;
  });
  return sharedInstance;
}

+ (instancetype)crashlytics {
  if (!sharedInstance) {
    FIRCLSErrorLog(@"[FIRCrashlytics startMonitoringWithDelegate:] must be called first.");
  }
  return sharedInstance;
}

- (void)setCrashlyticsCollectionEnabled:(BOOL)enabled {
  // Ignored in standalone Crashlytics
}

- (BOOL)isCrashlyticsCollectionEnabled {
  return YES;
}

#pragma mark - API: didCrashDuringPreviousExecution

- (BOOL)didCrashDuringPreviousExecution {
  return self.didPreviouslyCrash;
}

- (void)processDidCrashDuringPreviousExecution {
  NSString *crashedMarkerFileName = [NSString stringWithUTF8String:FIRCLSCrashedMarkerFileName];
  NSString *crashedMarkerFileFullPath =
      [[self.fileManager rootPath] stringByAppendingPathComponent:crashedMarkerFileName];
  self.didPreviouslyCrash = [self.fileManager fileExistsAtPath:crashedMarkerFileFullPath];

  if (self.didPreviouslyCrash) {
    // Delete the crash file marker in the background ensure start up is as fast as possible
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
      [self.fileManager removeItemAtPath:crashedMarkerFileFullPath];
    });
  }
}

#pragma mark - API: Custom Data

+ (void)updateCustomData:(NSDictionary<NSString *, NSString *> *)customData {
  [[self crashlytics] waitForContextInit:@"updateCustomData"
                                callback:^{
                                  FIRCLSUserLoggingRecordUserKeysAndValues(customData);
                                }];
}

#pragma mark - API: Errors and Exceptions
- (void)recordError:(NSError *)error {
  [self recordError:error userInfo:nil];
}

- (void)recordError:(NSError *)error userInfo:(NSDictionary<NSString *, id> *)userInfo {
  [self waitForContextInit:@"recordError"
                  callback:^{
                    FIRCLSUserLoggingRecordError(error, userInfo, nil);
                  }];
}

- (void)recordExceptionModel:(FIRExceptionModel *)exceptionModel {
  [self waitForContextInit:@"recordExceptionModel"
                  callback:^{
                    FIRCLSExceptionRecordModel(exceptionModel, nil);
                  }];
}

- (void)recordOnDemandExceptionModel:(FIRExceptionModel *)exceptionModel {
  [self waitForContextInit:@"recordOnDemandExceptionModel"
                  callback:^{
                    [self.managerData.onDemandModel
                        recordOnDemandExceptionIfQuota:exceptionModel
                             withDataCollectionEnabled:YES
                            usingExistingReportManager:self.existingReportManager];
                  }];
}

#pragma mark - Private Helpers
- (void)waitForContextInit:(NSString *)contextLog callback:(void (^)(void))callback {
  if (!_isContextInitialized) {
    FIRCLSErrorLog(@"PendoCrashReporter method called before SDK was initialized: %@", contextLog);
    return;
  }
  callback();
}
@end
