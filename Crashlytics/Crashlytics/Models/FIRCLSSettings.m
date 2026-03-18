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

#import "Crashlytics/Crashlytics/Models/FIRCLSSettings.h"

@implementation FIRCLSSettings

- (instancetype)init {
  self = [super init];
  if (!self) {
    return nil;
  }
  self.machExceptionDefaultBehavior = NO;
  return self;
}

- (BOOL)errorReportingEnabled {
  return YES;
}

- (BOOL)customExceptionsEnabled {
  return YES;
}

- (BOOL)collectReportsEnabled {
  return YES;
}

- (uint32_t)errorLogBufferSize {
  return [self logBufferSize];
}

- (uint32_t)logBufferSize {
  return 64 * 1000;
}

- (uint32_t)maxCustomExceptions {
  return 8;
}

- (uint32_t)maxCustomKeys {
  return 64;
}

- (double)onDemandUploadRate {
  return 10;
}

- (double)onDemandBackoffBase {
  return 1.5;
}

- (uint32_t)onDemandBackoffStepDuration {
  return 6;
}

- (BOOL)onDemandThreadSuspensionEnabled {
  return YES;
}

@end
