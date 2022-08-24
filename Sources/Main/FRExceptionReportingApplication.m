/*
 * Copyright 2008-2017, Jens Alfke, Torsten Curdt
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

#import "FRExceptionReportingApplication.h"
#import "FRFeedbackReporter.h"
#import <pthread.h>

@implementation FRExceptionReportingApplication

- (void) reportException:(NSException *)x
{
    assert(x);

    // we does not really want this, as this prevents our controller to be shown and shows a system-wide exception panel
    // NSApplication is documented to log, let it.
   // [super reportException: x];

    @try {
        // Cocoa's default behaviour here depends on the current thread.
        // For non-main threads, Cocoa will terminate the process.
        // For the main thread, it will not.
        // When an exception occurs, the process' internal state is likely
        // inconsistent/corrupt, so (in one school of thought) it's best
        // to kill the process.  On non-main threads, we don't intervene
        // and allow Cocoa to do so.  On the main thread however, we display
        // our 'exception occured' UI because if we killed the process with
        // abort(), the backtrace would be from here, not from where the
        // exception actually occured.
        if (!pthread_main_np()) {
            [[FRFeedbackReporter sharedReporter] performSelectorOnMainThread:@selector(reportException:) withObject:x waitUntilDone:NO];

            // We can't exit dispatch queue, so we make it sleep forever.
            BOOL isSimpleThread = ([[[NSThread callStackSymbols] lastObject]
                                    rangeOfString:@"thread_start"].location != NSNotFound);
            
            if (isSimpleThread) {
                [NSThread exit];
            } else {
                [NSThread sleepUntilDate:[NSDate distantFuture]];
            }
        } else {
            [[FRFeedbackReporter sharedReporter] reportException:x];
        }
    }
    @catch (NSException *exception) {

        NSLog(@"Problem within FeedbackReporter %@: %@  call stack:%@", [exception name], [exception reason], [exception callStackSymbols]);
    }
    @finally {
    }
}


@end
