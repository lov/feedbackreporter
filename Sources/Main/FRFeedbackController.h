/*
 * Copyright 2008-2017, Torsten Curdt
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <Cocoa/Cocoa.h>
#import "FRUploader.h"

NS_ASSUME_NONNULL_BEGIN

@protocol FRFeedbackReporterDelegate;

// Possibile values for setType:
#define FR_FEEDBACK  @"feedback"
#define FR_EXCEPTION @"exception"
#define FR_CRASH     @"crash"

@interface FRFeedbackController : NSWindowController <FRUploaderDelegate, NSWindowDelegate>

#pragma mark Accessors

@property (readwrite, weak, nonatomic) id<FRFeedbackReporterDelegate> delegate;

- (void) setHeading:(NSString*)message;
- (void) setSubheading:(NSString *)informativeText;
- (void) setMessage:(nullable NSString*)message;
- (void) setType:(NSString*)type;

@property (strong) NSString *exception;

#pragma mark UI

- (IBAction) showDetails:(id)sender;
- (IBAction) cancel:(id)sender;
- (IBAction) send:(id)sender;


#pragma mark Other

- (void) reset;
- (BOOL) isShown;

- (NSDictionary *)logsForSave;

@end

NS_ASSUME_NONNULL_END
