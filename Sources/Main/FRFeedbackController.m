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

#import "FRFeedbackController.h"
#import "FRFeedbackReporter.h"
#import "FRUploader.h"
#import "FRCommand.h"
#import "FRApplication.h"
#import "FRCrashLogFinder.h"
#import "FRSystemProfile.h"
#import "FRConstants.h"
#import "FRConsoleLog.h"
#import "FRLocalizedString.h"

#import "NSMutableDictionary+Additions.h"

#import <SystemConfiguration/SystemConfiguration.h>

// Private interface.
@interface FRFeedbackController()
@property (readwrite, strong, nonatomic) IBOutlet NSArrayController *systemDiscovery;

@property (readwrite, weak, nonatomic) IBOutlet NSTextField *headingField;
@property (readwrite, weak, nonatomic) IBOutlet NSTextField *subheadingField;

@property (readwrite, weak, nonatomic) IBOutlet NSTextField *messageLabel;
#if (MAC_OS_X_VERSION_MIN_REQUIRED < 101200)
@property (readwrite, assign, nonatomic) IBOutlet NSTextView *messageView;
#else
@property (readwrite, weak, nonatomic) IBOutlet NSTextView *messageView;
#endif

@property (readwrite, weak, nonatomic) IBOutlet NSTextField *emailLabel;
@property (readwrite, weak, nonatomic) IBOutlet NSTextField *emailField;

@property (readwrite, weak, nonatomic) IBOutlet NSButton *detailsButton;
@property (readwrite, weak, nonatomic) IBOutlet NSTextField *detailsLabel;

#if (MAC_OS_X_VERSION_MIN_REQUIRED < 101200)
@property (readwrite, assign, nonatomic) IBOutlet NSTextView *logView;
#else
@property (readwrite, weak, nonatomic) IBOutlet NSTextView *logView;
#endif



@property (readwrite, weak, nonatomic) IBOutlet NSProgressIndicator *indicator;

@property (readwrite, weak, nonatomic) IBOutlet NSButton *cancelButton;
@property (readwrite, weak, nonatomic) IBOutlet NSButton *sendButton;

@property (readwrite, nonatomic) BOOL detailsShown;
@property (readwrite, strong, nonatomic, nullable) FRUploader *uploader;
@property (readwrite, strong, nonatomic) NSString *type;
@end

@implementation FRFeedbackController

#pragma mark Construction

- (instancetype) init
{
    self = [super initWithWindowNibName:@"FeedbackReporter"];
    if (self != nil) {
        _detailsShown = YES;
    }
    return self;
}

#pragma mark Accessors

- (void) setHeading:(NSString*)message
{
    assert(message);
    [[self headingField] setStringValue:message];
}

- (void) setSubheading:(NSString *)informativeText
{
    assert(informativeText);
    [[self subheadingField] setStringValue:informativeText];
}

- (void) setMessage:(nullable NSString*)message
{
    [[self messageView] setString:message];
}

#pragma mark information gathering

- (NSString*) consoleLog
{
    NSNumber *hours = [[[NSBundle mainBundle] infoDictionary] objectForKey:PLIST_KEY_LOGHOURS];

  //  int h = 24;
    int h = 1;
    
    if (hours != nil) {
        h = [hours intValue];
    }

    NSDate *since = [NSDate dateWithTimeIntervalSinceNow:-h * 60.0 * 60.0];

    NSNumber *maximumSize = [[[NSBundle mainBundle] infoDictionary] objectForKey:PLIST_KEY_MAXCONSOLELOGSIZE];

    return [FRConsoleLog logSince:since maxSize:maximumSize];
}


- (NSArray*) systemProfile
{
    static NSArray *systemProfile = nil;

    static dispatch_once_t predicate = 0;
    dispatch_once(&predicate, ^{ systemProfile = [FRSystemProfile discover]; });

    return systemProfile;
}

- (NSString*) systemProfileAsString
{
    NSMutableString *string = [NSMutableString string];
    NSArray *dicts = [self systemProfile];
    for (NSDictionary *dict in dicts) {
        [string appendFormat:@"%@ = %@\n", [dict objectForKey:@"key"], [dict objectForKey:@"value"]];
    }
    return string;
}

- (NSString*) crashLog
{
    NSDate *lastSubmissionDate = [[NSUserDefaults standardUserDefaults] objectForKey:DEFAULTS_KEY_LASTSUBMISSIONDATE];
    if (lastSubmissionDate && ![lastSubmissionDate isKindOfClass:[NSDate class]]) {
        lastSubmissionDate = nil;
    }

    NSArray *crashFiles = [FRCrashLogFinder findCrashLogsSince:lastSubmissionDate];

    NSUInteger i = [crashFiles count];

    if (i == 1) {
        if (lastSubmissionDate == nil) {
            NSLog(@"Found a crash file");
        } else {
            NSLog(@"Found a crash file earlier than latest submission on %@", lastSubmissionDate);
        }
        NSError *error = nil;
        NSString *result = [NSString stringWithContentsOfFile:[crashFiles lastObject] encoding: NSUTF8StringEncoding error:&error];
        if (result == nil) {
            NSLog(@"Failed to read crash file: %@", error);
            return @"";
        }
        return result;
    }

    if (lastSubmissionDate == nil) {
        NSLog(@"Found %lu crash files", (unsigned long)i);
    } else {
        NSLog(@"Found %lu crash files earlier than latest submission on %@", (unsigned long)i, lastSubmissionDate);
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSDate *newest = nil;
    NSInteger newestIndex = -1;

    while(i--) {

        NSString *crashFile = [crashFiles objectAtIndex:i];
        NSError* error = nil;
        NSDictionary *fileAttributes = [fileManager attributesOfItemAtPath:crashFile error:&error];
        if (!fileAttributes) {
            NSLog(@"Error while fetching file attributes: %@", [error localizedDescription]);
        }
        NSDate *fileModDate = [fileAttributes objectForKey:NSFileModificationDate];

        NSLog(@"CrashLog: %@", crashFile);

        if ([fileModDate laterDate:newest] == fileModDate) {
            newest = fileModDate;
            newestIndex = i;
        }

    }

    if (newestIndex != -1) {
        NSString *newestCrashFile = [crashFiles objectAtIndex:newestIndex];

        NSLog(@"Picking CrashLog: %@", newestCrashFile);

        NSError *error = nil;
        NSString *result = [NSString stringWithContentsOfFile:newestCrashFile encoding: NSUTF8StringEncoding error:&error];
        if (result == nil) {
            NSLog(@"Failed to read crash file: %@", error);
            return @"";
        }
        return result;
    }

    return @"";
}

- (NSString*) scriptLog
{
    NSMutableString *scriptLog = [NSMutableString string];

    NSURL *scriptFileURL = [[NSBundle mainBundle] URLForResource:@"FRFeedbackReporter" withExtension:@"sh"];

    if (scriptFileURL) {
        FRCommand *cmd = [[FRCommand alloc] initWithFileURL:scriptFileURL args:@[]];
        [cmd setOutput:scriptLog];
        [cmd setError:scriptLog];
        int ret = [cmd execute];

        NSLog(@"Script exit code = %d", ret);
    }

    return scriptLog;
}

- (NSString*) preferences
{
    NSMutableDictionary *preferences = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:[FRApplication applicationIdentifier]] mutableCopy];

    if (preferences == nil) {
        return @"";
    }

    // why would we reset this?
//    [preferences removeObjectForKey:DEFAULTS_KEY_SENDEREMAIL];

    id<FRFeedbackReporterDelegate> strongDelegate = [self delegate];
    if ([strongDelegate respondsToSelector:@selector(anonymizePreferencesForFeedbackReport:)]) {
        NSDictionary *newPreferences = [strongDelegate anonymizePreferencesForFeedbackReport:preferences];
        assert(newPreferences);
        return [NSString stringWithFormat:@"%@", newPreferences];
    }
    else {
        return [NSString stringWithFormat:@"%@", preferences];
    }
}

#pragma mark Collecting for Save

- (NSDictionary *)logsForSave {

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    
    [dict setValidString:[FRApplication applicationShortVersion]
                  forKey:POST_KEY_VERSION_SHORT];
    
    [dict setValidString:[FRApplication applicationBundleVersion]
                  forKey:POST_KEY_VERSION_BUNDLE];
    
    [dict setValidString:[FRApplication applicationVersion]
                  forKey:POST_KEY_VERSION];
    
    id<FRFeedbackReporterDelegate> strongDelegate = [self delegate];
    
    if ([strongDelegate respondsToSelector:@selector(customParametersForFeedbackReport)]) {
        NSDictionary *customParams = [strongDelegate customParametersForFeedbackReport];
        if (customParams) {
            [dict addEntriesFromDictionary:customParams];
        }
    }
    
    [dict setValidString:[self systemProfileAsString]
                  forKey:POST_KEY_SYSTEM];
    
    [dict setValidString:[self crashLog]
                  forKey:POST_KEY_CRASHES];
    
    [dict setValidString:[self preferences]
                  forKey:POST_KEY_PREFERENCES];
        
    return dict;
}

#pragma mark UI Actions

- (void) showDetails:(BOOL)show animate:(BOOL)animate
{
    if ([self detailsShown] == show) {
        return;
    }

    NSSize fullSize = NSMakeSize(455, 302);

    NSRect windowFrame = [[self window] frame];

    if (show) {

        windowFrame.origin.y -= fullSize.height;
        windowFrame.size.height += fullSize.height;
        [[self window] setFrame: windowFrame
                        display: YES
                        animate: animate];
        

    } else {
        windowFrame.origin.y += fullSize.height;
        windowFrame.size.height -= fullSize.height;
        [[self window] setFrame: windowFrame
                        display: YES
                        animate: animate];

    }

    [self setDetailsShown:show];
    
}

- (IBAction) showDetails:(id)sender
{
    assert([sender isKindOfClass:[NSControl class]]);
    BOOL show = [[sender objectValue] boolValue];
    [self showDetails:show animate:YES];
}

- (IBAction) cancel:(id)sender
{
    (void)sender;

    [[self uploader] cancel];
    [self setUploader:nil];

    [self close];
}

- (IBAction) send:(id)sender
{
    (void)sender;

    if ([self uploader] != nil) {
        NSLog(@"Still uploading");
        return;
    }

    NSURL *url = nil;

    id<FRFeedbackReporterDelegate> strongDelegate = [self delegate];
    if ([strongDelegate respondsToSelector:@selector(targetURLForFeedbackReport)]) {
        url = [strongDelegate targetURLForFeedbackReport];
        assert(url);
    }
    else {
	    NSString *target = [[FRApplication feedbackURL] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
	    if (url == nil) {
            NSLog(@"You are missing the %@ key in your Info.plist!", PLIST_KEY_TARGETURL);
            return;
        }
	    url = [NSURL URLWithString:target];
    }

    SCNetworkConnectionFlags reachabilityFlags = 0;

    NSString *host = [url host];
    const char *hostname = [host UTF8String];

    Boolean reachabilityResult = false;
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, hostname);
    if (reachability) {
        reachabilityResult = SCNetworkReachabilityGetFlags(reachability, &reachabilityFlags);
        CFRelease(reachability);
    }

    BOOL reachable = reachabilityResult
        &&  (reachabilityFlags & kSCNetworkFlagsReachable)
        && !(reachabilityFlags & kSCNetworkFlagsConnectionRequired)
        && !(reachabilityFlags & kSCNetworkFlagsConnectionAutomatic)
        && !(reachabilityFlags & kSCNetworkFlagsInterventionRequired);

    if (!reachable) {
        NSString *fullName = [NSString stringWithFormat:@"%@://%@", [url scheme], host];
        
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:FRLocalizedString(@"Proceed Anyway", nil)];
        [alert addButtonWithTitle:FRLocalizedString(@"Cancel", nil)];
        [alert setMessageText:FRLocalizedString(@"Feedback Host Not Reachable", nil)];
        [alert setInformativeText:[NSString stringWithFormat:FRLocalizedString(@"You may not be able to send feedback because %@ isn't reachable.", nil), fullName]];
        NSInteger alertResult = [alert runModal];

        if (alertResult != NSAlertFirstButtonReturn) {
            return;
        }
    }

    FRUploader* uploader = [[FRUploader alloc] initWithTargetURL:url delegate:self];
    [self setUploader:uploader];

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    [dict setValidString:[[self emailField] stringValue]
                  forKey:POST_KEY_EMAIL];

    [dict setValidString:[[self messageView] string]
                  forKey:POST_KEY_MESSAGE];

    [dict setValidString:[self type]
                  forKey:POST_KEY_TYPE];

    [dict setValidString:[FRApplication applicationShortVersion]
                  forKey:POST_KEY_VERSION_SHORT];

    [dict setValidString:[FRApplication applicationBundleVersion]
                  forKey:POST_KEY_VERSION_BUNDLE];

    [dict setValidString:[FRApplication applicationVersion]
                  forKey:POST_KEY_VERSION];

    if ([strongDelegate respondsToSelector:@selector(customParametersForFeedbackReport)]) {
        NSDictionary *customParams = [strongDelegate customParametersForFeedbackReport];
        if (customParams) {
            [dict addEntriesFromDictionary:customParams];
        }
    }

    [dict setValidString:[self systemProfileAsString]
                  forKey:POST_KEY_SYSTEM];

    [dict setValidString:[self crashLog]
                  forKey:POST_KEY_CRASHES];
    
    [dict setValidString:[self exception]
                    forKey:POST_KEY_EXCEPTION];

    
    [dict setValidString:[self preferences]
                  forKey:POST_KEY_PREFERENCES];

    NSLog(@"Sending feedback to %@", url);

    [uploader postAndNotify:dict];
}

- (void) uploaderStarted:(FRUploader*)pUploader
{
    assert(pUploader); (void)pUploader;

    // NSLog(@"Upload started");

    [[self indicator] setHidden:NO];
    [[self indicator] startAnimation:self];

    [[self messageView] setEditable:NO];
    [[self sendButton] setEnabled:NO];
}

- (void) uploaderFailed:(FRUploader*)pUploader withError:(NSError*)error
{
    assert(pUploader); (void)pUploader;

    NSLog(@"Upload failed: %@", error);

    [[self indicator] stopAnimation:self];
    [[self indicator] setHidden:YES];

    [self setUploader:nil];

    [[self messageView] setEditable:YES];
    [[self sendButton] setEnabled:YES];

    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:FRLocalizedString(@"OK", nil)];
    [alert setMessageText:FRLocalizedString(@"Sorry, failed to submit your feedback to the server.", nil)];
    [alert setInformativeText:[NSString stringWithFormat:FRLocalizedString(@"Error: %@", nil), [error localizedDescription]]];
    [alert setAlertStyle:NSWarningAlertStyle];
    [alert runModal];

    [self close];
}

- (void) uploaderFinished:(FRUploader*)pUploader
{
    assert(pUploader); (void)pUploader;

    // NSLog(@"Upload finished");

    [[self indicator] stopAnimation:self];
    [[self indicator] setHidden:YES];

    NSString *response = [[self uploader] response];

    [self setUploader:nil];

    [[self messageView] setEditable:YES];
    [[self sendButton] setEnabled:YES];

    NSArray *lines = [response componentsSeparatedByString:@"\n"];
    for (NSString *line in [lines reverseObjectEnumerator]) {
        if ([line length] == 0) {
            continue;
        }

        if (![line hasPrefix:@"OK "]) {

            NSLog (@"Failed to submit to server: %@", response);

            NSAlert *alert = [[NSAlert alloc] init];
            [alert addButtonWithTitle:FRLocalizedString(@"OK", nil)];
            [alert setMessageText:FRLocalizedString(@"Sorry, failed to submit your feedback to the server.", nil)];
            [alert setInformativeText:[NSString stringWithFormat:FRLocalizedString(@"Error: %@", nil), line]];
            [alert setAlertStyle:NSWarningAlertStyle];
            [alert runModal];

            return;
        }
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:[NSDate date]
                                              forKey:DEFAULTS_KEY_LASTSUBMISSIONDATE];
    
    [[NSUserDefaults standardUserDefaults] setObject:[[self emailField] stringValue]
                                              forKey:DEFAULTS_KEY_SENDEREMAIL];

    [self close];
}

- (void) windowWillClose: (NSNotification *) n
{
    assert(n); (void)n;

    [[self uploader] cancel];

    if ([[self type] isEqualToString:FR_EXCEPTION]) {
        // We want a pure exit() here I think.
        // As an exception has already been raised there is no
        // guarantee that the code path to [NSAapp terminate] is functional.
        // Calling abort() will crash the app here but is that more desirable?
        exit(EXIT_FAILURE);
    }
}

- (void) windowDidLoad
{
    [[self window] setDelegate:self];

    [[self window] setTitle:FRLocalizedString(@"Feedback", nil)];

    [[self emailLabel] setStringValue:FRLocalizedString(@"Email address:", nil)];
    [[self detailsLabel] setStringValue:FRLocalizedString(@"Details", nil)];
    
    [[self logView] setString:@""];

    [[self sendButton] setTitle:FRLocalizedString(@"Send", nil)];
    [[self cancelButton] setTitle:FRLocalizedString(@"Cancel", nil)];

}

- (void) stopSpinner
{
    [[self indicator] stopAnimation:self];
    [[self indicator] setHidden:YES];
    [[self sendButton] setEnabled:YES];
}


- (void) populate
{
    @autoreleasepool {
        
        
        /*
         NSString *consoleLog = [self consoleLog];
        if ([consoleLog length] > 0) {
            [self performSelectorOnMainThread:@selector(addTabViewItem:) withObject:[self tabConsole] waitUntilDone:YES];
            [[self consoleView] performSelectorOnMainThread:@selector(setString:) withObject:consoleLog waitUntilDone:YES];
        }
         */
        
        NSString *logs = @"";
        NSDictionary *logsforsave = [self logsForSave];
        
        for (NSString *current in [logsforsave allKeys]) {
            
            logs = [NSString stringWithFormat:@"%@%@->\n %@\n---\n\n", logs,current, [logsforsave objectForKey:current]];
        }
        
        [[self logView] performSelectorOnMainThread:@selector(setString:) withObject:logs waitUntilDone:YES];

        [self performSelectorOnMainThread:@selector(stopSpinner) withObject:self waitUntilDone:YES];
    }
}

- (void) reset
{
    [[self logView] setString:@""];
    
    [self setException:@""];

    [[self emailField] setStringValue:@""];
    
    NSString *email = [[NSUserDefaults standardUserDefaults] stringForKey:DEFAULTS_KEY_SENDEREMAIL];
    if (email) {
        [[self emailField] setStringValue:email];
    }

    [[self headingField] setStringValue:@""];
    [[self messageView] setString:@""];

    [self showDetails:NO animate:NO];
    [[self detailsButton] setIntValue:NO];

    [[self indicator] setHidden:NO];
    [[self indicator] startAnimation:self];
    [[self sendButton] setEnabled:NO];

}

- (void) showWindow:(id)sender
{
    if ([[self type] isEqualToString:FR_FEEDBACK]) {
        [[self messageLabel] setStringValue:FRLocalizedString(@"Feedback comment label", nil)];
    } else {
        [[self messageLabel] setStringValue:FRLocalizedString(@"Comments:", nil)];
    }

    [NSThread detachNewThreadSelector:@selector(populate) toTarget:self withObject:nil];

    [super showWindow:sender];
}

- (BOOL) isShown
{
    return [[self window] isVisible];
}

@end
