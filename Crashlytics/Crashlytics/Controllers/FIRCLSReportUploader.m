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
#import "Crashlytics/Crashlytics/Controllers/FIRCLSReportUploader.h"
#import "Crashlytics/Crashlytics/DataCollection/FIRCLSDataCollectionToken.h"
#import "Crashlytics/Crashlytics/Helpers/FIRCLSDefines.h"
#import "Crashlytics/Crashlytics/Helpers/FIRCLSFile.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSFileManager.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSInternalReport.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSSettings.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSSymbolResolver.h"
#import "Crashlytics/Crashlytics/Operations/Reports/FIRCLSProcessReportOperation.h"
#import "Crashlytics/Crashlytics/Public/FirebaseCrashlytics/FIRCrashlytics.h"

#include "Crashlytics/Crashlytics/Helpers/FIRCLSUtility.h"

#import "Crashlytics/Shared/FIRCLSConstants.h"
#import "Crashlytics/Shared/FIRCLSNetworking/FIRCLSURLBuilder.h"


@interface FIRCLSReportUploader ()

- (NSDictionary *)parseCrashReportAtPath:(NSString *)path;

@end

@implementation FIRCLSReportUploader

- (instancetype)initWithManagerData:(FIRCLSManagerData *)managerData {
  self = [super init];
  if (!self) {
    return nil;
  }

  _operationQueue = managerData.operationQueue;
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
      FIRCLSApplicationActivityDefault, @"PendoCrashReporter Crash Report Processing", ^{
        
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

        FIRCLSInfoLog(@"[PendoCrashReporter] Packaged report with id '%@' for submission",
                      report.identifier);

        // Parse the report and notify the delegate
        NSDictionary *parsedReport = [self parseCrashReportAtPath:packagedPath];
        id<PNDCrashReporterDelegate> delegate = [FIRCrashlytics crashlytics].delegate;
        if ([delegate respondsToSelector:@selector(crashReporterDidDetectCrashReport:)]) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [delegate crashReporterDidDetectCrashReport:parsedReport];
          });
        }

        // In a standalone crash reporter, the report is now sitting in the "prepared" folder.
        // We clean it up so it doesn't pile up.
        [self cleanUpSubmittedReportAtPath:packagedPath];
      });

  return;
}

- (NSDictionary *)parseCrashReportAtPath:(NSString *)path {
  NSMutableDictionary *reportDict = [NSMutableDictionary dictionary];
  
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSArray *files = [fileManager contentsOfDirectoryAtPath:path error:nil];
  
  for (NSString *filename in files) {
    if (![filename hasSuffix:@".clsrecord"] && ![filename hasSuffix:@".clsrecord.symbolicated"]) {
      continue;
    }
    
    // Ignore log files entirely as requested
    if ([filename containsString:@"log"]) {
      continue;
    }
    
    NSString *fullPath = [path stringByAppendingPathComponent:filename];
    NSString *key = [filename stringByDeletingPathExtension];
    if ([filename hasSuffix:@".clsrecord.symbolicated"]) {
        // key is currently "exception.clsrecord", change it to "exception_symbolicated"
        key = [[key stringByDeletingPathExtension] stringByAppendingString:@"_symbolicated"];
    }
    
    BOOL isKVFile = [filename containsString:@"kv"];
    NSMutableDictionary *fileDict = [NSMutableDictionary dictionary];
    
    NSArray *sections = FIRCLSFileReadSections([fullPath UTF8String], NO, ^NSObject *(id obj) {
      if (![obj isKindOfClass:[NSDictionary class]]) {
        return obj;
      }
      NSMutableDictionary *dict = [(NSDictionary *)obj mutableCopy];
      
      // Decode errors (domain and userInfo can contain arbitrary strings, so they use hex)
      if (dict[@"error"]) {
        NSMutableDictionary *err = [dict[@"error"] mutableCopy];
        if (err[@"domain"]) err[@"domain"] = FIRCLSFileHexDecodeString([err[@"domain"] UTF8String]) ?: err[@"domain"];
        
        for (NSString *infoKey in @[@"info", @"extra_info"]) {
          if (err[infoKey] && [err[infoKey] isKindOfClass:[NSArray class]]) {
            NSMutableArray *newInfo = [NSMutableArray array];
            for (id item in err[infoKey]) {
              if ([item isKindOfClass:[NSArray class]] && [item count] == 2) {
                NSString *k = FIRCLSFileHexDecodeString([item[0] UTF8String]) ?: item[0];
                NSString *v = FIRCLSFileHexDecodeString([item[1] UTF8String]) ?: item[1];
                [newInfo addObject:@[k, v]];
              } else {
                [newInfo addObject:item];
              }
            }
            err[infoKey] = newInfo;
          }
        }
        dict[@"error"] = err;
      }
      
      return dict;
    });
    
    if (sections) {
      if (isKVFile) {
        // Flatten KV arrays into a direct key-value dictionary
        for (NSDictionary *section in sections) {
          NSDictionary *kv = section[@"kv"];
          if (kv && kv[@"key"] && kv[@"value"] && ![kv[@"value"] isEqual:[NSNull null]]) {
            fileDict[kv[@"key"]] = kv[@"value"];
          }
        }
      } else {
        // Merge JSON-Lines into a single dictionary of dictionaries.
        // If a root key (like "exception" or "thread") appears multiple times, group them into an array.
        for (NSDictionary *section in sections) {
          for (NSString *sectionKey in section) {
            id sectionValue = section[sectionKey];
            id existingValue = fileDict[sectionKey];
            
            if (existingValue) {
              if ([existingValue isKindOfClass:[NSMutableArray class]]) {
                [(NSMutableArray *)existingValue addObject:sectionValue];
              } else {
                fileDict[sectionKey] = [@[existingValue, sectionValue] mutableCopy];
              }
            } else {
              fileDict[sectionKey] = sectionValue;
            }
          }
        }
      }
      
      [reportDict setObject:fileDict forKey:key];
    }
  }
  
  return [reportDict copy];
}



- (BOOL)cleanUpSubmittedReportAtPath:(NSString *)path {
  if (![[self fileManager] removeItemAtPath:path]) {
    FIRCLSErrorLog(@"Unable to remove packaged submission");
    return NO;
  }

  return YES;
}

@end
