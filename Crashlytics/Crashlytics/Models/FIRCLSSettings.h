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

NS_ASSUME_NONNULL_BEGIN

@interface FIRCLSSettings : NSObject

- (instancetype)init;

@property(nonatomic, readonly) BOOL collectReportsEnabled;
@property(nonatomic, readonly) BOOL errorReportingEnabled;
@property(nonatomic, readonly) BOOL customExceptionsEnabled;
@property(nonatomic) BOOL machExceptionDefaultBehavior;
@property(nonatomic, readonly) uint32_t errorLogBufferSize;
@property(nonatomic, readonly) uint32_t logBufferSize;
@property(nonatomic, readonly) uint32_t maxCustomExceptions;
@property(nonatomic, readonly) uint32_t maxCustomKeys;
@property(nonatomic, readonly) double onDemandUploadRate;
@property(nonatomic, readonly) double onDemandBackoffBase;
@property(nonatomic, readonly) uint32_t onDemandBackoffStepDuration;
@property(nonatomic, readonly) BOOL onDemandThreadSuspensionEnabled;

@end

NS_ASSUME_NONNULL_END
