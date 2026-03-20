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

#import "Crashlytics/Crashlytics/Components/FIRCLSApplication.h"
#import "Crashlytics/Crashlytics/Components/FIRCLSUserLogging.h"
#import "Crashlytics/Crashlytics/Controllers/FIRCLSContextManager.h"
#import "Crashlytics/Crashlytics/Controllers/FIRCLSExistingReportManager.h"
#import "Crashlytics/Crashlytics/Controllers/FIRCLSManagerData.h"
#import "Crashlytics/Crashlytics/Controllers/FIRCLSNotificationManager.h"
#import "Crashlytics/Crashlytics/DataCollection/FIRCLSDataCollectionToken.h"
#import "Crashlytics/Crashlytics/Helpers/FIRCLSDefines.h"
#import "Crashlytics/Crashlytics/Helpers/FIRCLSFeatures.h"
#import "Crashlytics/Crashlytics/Helpers/FIRCLSLogger.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSFileManager.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSInternalReport.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSLaunchMarkerModel.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSSettings.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSSymbolResolver.h"
#import "Crashlytics/Crashlytics/Operations/Reports/FIRCLSProcessReportOperation.h"

#include "Crashlytics/Crashlytics/Components/FIRCLSGlobals.h"
#include "Crashlytics/Crashlytics/Helpers/FIRCLSUtility.h"

#import "Crashlytics/Crashlytics/Models/FIRCLSExecutionIdentifierModel.h"
#import "Crashlytics/Shared/FIRCLSConstants.h"

#import "Crashlytics/Crashlytics/Controllers/FIRCLSReportManager_Private.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

@interface FIRCLSReportManager () {
  FIRCLSFileManager *_fileManager;
  dispatch_queue_t _dispatchQueue;
  NSOperationQueue *_operationQueue;
  
  atomic_bool _checkForUnsentReportsCalled;
}

@property(nonatomic, strong) FIRCLSSettings *settings;
@property(nonatomic, strong) FIRCLSLaunchMarkerModel *launchMarker;

@property(nonatomic, strong) FIRCLSExecutionIdentifierModel *executionIDModel;

@property(nonatomic, strong) FIRCLSExistingReportManager *existingReportManager;

@property(nonatomic, strong) FIRCLSContextManager *contextManager;

@property(nonatomic, strong) FIRCLSNotificationManager *notificationManager;

@end

@implementation FIRCLSReportManager

- (instancetype)initWithManagerData:(FIRCLSManagerData *)managerData
              existingReportManager:(FIRCLSExistingReportManager *)existingReportManager {
  self = [super init];
  if (!self) {
    return nil;
  }

  _fileManager = managerData.fileManager;
  _operationQueue = managerData.operationQueue;
  _dispatchQueue = managerData.dispatchQueue;
  _settings = managerData.settings;
  _executionIDModel = managerData.executionIDModel;
  _contextManager = managerData.contextManager;

  _existingReportManager = existingReportManager;

  _checkForUnsentReportsCalled = NO;

  _notificationManager = [[FIRCLSNotificationManager alloc] init];


  _launchMarker = [[FIRCLSLaunchMarkerModel alloc] initWithFileManager:_fileManager];

  return self;
}


- (BOOL)startWithProfiling {
  NSString *executionIdentifier = self.executionIDModel.executionID;

  [self.existingReportManager collectExistingReports];

#if DEBUG
  FIRCLSDebugLog(@"Root: %@", [_fileManager rootPath]);
#endif

  if (![_fileManager createReportDirectories]) {
    return NO;
  }

  BOOL launchFailure = [self.launchMarker checkForAndCreateLaunchMarker];

  FIRCLSInternalReport *report = [self setupCurrentReport:executionIdentifier];
  if (!report) {
    FIRCLSErrorLog(@"Unable to setup a new report");
    return NO;
  }

  BOOL started = [self startCrashReporterWithProfilingReport:report];
  if (!started) {
    FIRCLSErrorLog(@"Unable to start crash reporter");
    return NO;
  }

  dispatch_async(FIRCLSGetLoggingQueue(), ^{
    FIRCLSUserLoggingWriteInternalKeyValue(FIRCLSStartTimeKey, @"");
  });

  FIRCLSDataCollectionToken *dataCollectionToken = [FIRCLSDataCollectionToken validToken];
  [self beginReportUploadsWithToken:dataCollectionToken blockingSend:launchFailure];

  return YES;
}

- (void)beginReportUploadsWithToken:(FIRCLSDataCollectionToken *)token
                       blockingSend:(BOOL)blockingSend {
  if (self.settings.collectReportsEnabled) {
    [self.existingReportManager sendUnsentReportsWithToken:token asUrgent:blockingSend];
  } else {
    FIRCLSInfoLog(@"Collect crash reports is disabled");
    [self.existingReportManager deleteUnsentReports];
  }
}

- (BOOL)startCrashReporterWithProfilingReport:(FIRCLSInternalReport *)report {
  if (!report) {
    return NO;
  }

  [self.contextManager setupContextWithReport:report
                                     settings:self.settings
                                  fileManager:_fileManager];
                                  
  [self.notificationManager registerNotificationListener];

  [self crashReportingSetupCompleted];

  return YES;
}

- (void)crashReportingSetupCompleted {
  FIRCLSDispatchAfter(2.0, dispatch_get_main_queue(), ^{
    FIRCLSExceptionCheckHandlers((__bridge void *)(self));
#if CLS_SIGNAL_SUPPORTED
    FIRCLSSignalCheckHandlers();
#endif
#if CLS_MACH_EXCEPTION_SUPPORTED
    FIRCLSMachExceptionCheckHandlers();
#endif
  });

  dispatch_async(dispatch_get_main_queue(), ^{
    [self.launchMarker removeLaunchFailureMarker];
    dispatch_async(FIRCLSGetLoggingQueue(), ^{
      FIRCLSUserLoggingWriteInternalKeyValue(FIRCLSFirstRunloopTurnTimeKey, @"");
    });
  });
}

- (FIRCLSInternalReport *)setupCurrentReport:(NSString *)executionIdentifier {
  [self.launchMarker createLaunchFailureMarker];

  NSString *reportPath = [_fileManager setupNewPathForExecutionIdentifier:executionIdentifier];

  if (!reportPath) {
      return nil;
  }

  return [[FIRCLSInternalReport alloc] initWithPath:reportPath
                                executionIdentifier:executionIdentifier];
}

@end
