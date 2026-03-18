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


#import "Crashlytics/Crashlytics/Components/FIRCLSApplication.h"
#import "Crashlytics/Crashlytics/Controllers/FIRCLSManagerData.h"
#import "Crashlytics/Crashlytics/Controllers/FIRCLSReportUploader_Private.h"
#import "Crashlytics/Crashlytics/DataCollection/FIRCLSDataCollectionToken.h"
#import "Crashlytics/Crashlytics/Helpers/FIRCLSDefines.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSFileManager.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSInstallIdentifierModel.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSInternalReport.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSSettings.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSSymbolResolver.h"
#import "Crashlytics/Crashlytics/Operations/Reports/FIRCLSProcessReportOperation.h"

#include "Crashlytics/Crashlytics/Helpers/FIRCLSUtility.h"

#import "Crashlytics/Shared/FIRCLSConstants.h"
#import "Crashlytics/Shared/FIRCLSNetworking/FIRCLSURLBuilder.h"


@interface FIRCLSReportUploader ()
@property(nonatomic, strong) FIRCLSInstallIdentifierModel *installIDModel;

@property(nonatomic, readonly) NSString *googleAppID;

@end

@implementation FIRCLSReportUploader

- (instancetype)initWithManagerData:(FIRCLSManagerData *)managerData {
  self = [super init];
  if (!self) {
    return nil;
  }

  _operationQueue = managerData.operationQueue;
  _googleAppID = managerData.googleAppID;
  _installIDModel = managerData.installIDModel;
  _fileManager = managerData.fileManager;

  return self;
}

#pragma mark - Packaging and Submission

/*
 * For a crash report, this is the initial code path for uploading. A report
 * will not repeat this code path after it's happened because this code path
 * will move the report from the "active" folder into "processing" and then
 * "prepared". Once in prepared, the report can be re-uploaded any number of times
 * with uploadPackagedReportAtPath in the case of an upload failure.
 */
- (void)prepareAndSubmitReport:(FIRCLSInternalReport *)report
           dataCollectionToken:(FIRCLSDataCollectionToken *)dataCollectionToken
                      asUrgent:(BOOL)urgent
                withProcessing:(BOOL)shouldProcess {
  if (![dataCollectionToken isValid]) {
    FIRCLSErrorLog(@"Data collection disabled and report will not be submitted");
    return;
  }

  // This activity is still relevant using GoogleDataTransport because the on-device
  // symbolication operation may be computationally intensive.
  FIRCLSApplicationActivity(
      FIRCLSApplicationActivityDefault, @"Crashlytics Crash Report Processing", ^{
        // Check to see if the FID has rotated before we construct the payload
        // so that the payload has an updated value.
        //
        // If we're in urgent mode, this will be running on the main thread. Since
        // the FIID callback is run on the main thread, this call can deadlock in
        // urgent mode. Since urgent mode happens when the app is in a crash loop,
        // we can safely assume users aren't rotating their FIID, so this can be skipped.
        if (!urgent) {
          [self.installIDModel regenerateInstallIDIfNeededWithBlock:^(
                                   NSString *_Nonnull newFIID, NSString *_Nonnull authToken) {
            self.fiid = [newFIID copy];
            self.authToken = [authToken copy];
          }];
        } else {
          FIRCLSWarningLog(
              @"Crashlytics skipped rotating the Install ID during urgent mode because it is run "
              @"on the main thread, which can't succeed. This can happen if the app crashed the "
              @"last run and Crashlytics is uploading urgently.");
        }

        // Run on-device symbolication before packaging if we should process
        if (shouldProcess) {
          if (![self.fileManager moveItemAtPath:report.path
                                    toDirectory:self.fileManager.processingPath]) {
            FIRCLSErrorLog(@"Unable to move report for processing");
            return;
          }

          // adjust the report's path, and process it
          [report setPath:[self.fileManager.processingPath
                              stringByAppendingPathComponent:report.directoryName]];

          FIRCLSSymbolResolver *resolver = [[FIRCLSSymbolResolver alloc] init];

          FIRCLSProcessReportOperation *processOperation =
              [[FIRCLSProcessReportOperation alloc] initWithReport:report resolver:resolver];

          [processOperation start];
        }

        // With the new report endpoint, the report is deleted once it is written to GDT
        // Check if the report has a crash file before the report is moved or deleted
        BOOL isCrash = report.isCrash;

        // For the new endpoint, just move the .clsrecords from "processing" -> "prepared".
        // In the old endpoint this was for packaging the report as a multipartmime file,
        // so this can probably be removed for GoogleDataTransport.
        if (![self.fileManager moveItemAtPath:report.path
                                  toDirectory:self.fileManager.preparedPath]) {
          FIRCLSErrorLog(@"Unable to move report to prepared");
          return;
        }

        NSString *packagedPath = [self.fileManager.preparedPath
            stringByAppendingPathComponent:report.path.lastPathComponent];

        FIRCLSInfoLog(@"[Firebase/Crashlytics] Packaged report with id '%@' for submission",
                      report.identifier);

        // In a standalone crash reporter, the report is now sitting in the "prepared" folder.
        // It is up to the host application to pick it up from here.
      });

  return;
}



- (BOOL)cleanUpSubmittedReportAtPath:(NSString *)path {
  if (![[self fileManager] removeItemAtPath:path]) {
    FIRCLSErrorLog(@"Unable to remove packaged submission");
    return NO;
  }

  return YES;
}

@end
