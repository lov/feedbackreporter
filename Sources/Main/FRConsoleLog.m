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

#import "FRConsoleLog.h"
#import "FRConstants.h"
#import "FRApplication.h"

#import <asl.h>
#import <unistd.h>

#define FR_CONSOLELOG_TIME 0
#define FR_CONSOLELOG_TEXT 1
#define FR_CONSOLELOG_SENDER 2
//#define FR_CONSOLELOG_APP_ONLY

@implementation FRConsoleLog

+ (NSString*) logSince:(NSDate*)since maxSize:(nullable NSNumber*)maximumSize
{
    NSUInteger consoleOutputLength = 0;
    NSUInteger rawConsoleLinesCapacity = 100;
    NSUInteger consoleLinesProcessed = 0;

    char ***rawConsoleLines = malloc(rawConsoleLinesCapacity * sizeof(char **));
    NSMutableString *consoleString = [[NSMutableString alloc] init];
    NSMutableArray *consoleLines = [[NSMutableArray alloc] init];

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
    [dateFormatter setTimeStyle:NSDateFormatterMediumStyle];
    
    // ASL does not work in App Sandbox, even read-only. <rdar://problem/9689364>
    // Workaround is to use:
    //   com.apple.security.temporary-exception.files.absolute-path.read-only
    // for:
    //   /private/var/log/asl/
    aslmsg query = asl_new(ASL_TYPE_QUERY);
    
    if (query != NULL) {

        NSString *sinceString = [NSString stringWithFormat:@"%01f", [since timeIntervalSince1970]];
        asl_set_query(query, ASL_KEY_TIME, [sinceString UTF8String], ASL_QUERY_OP_GREATER_EQUAL);
        // Prevent premature garbage collection (UTF8String returns an inner pointer).
        [sinceString self];
        
#ifdef FR_CONSOLELOG_APP_ONLY
        NSString *applicationName = [FRApplication applicationName];
        asl_set_query(query, ASL_KEY_SENDER, [applicationName UTF8String], ASL_QUERY_OP_EQUAL);
        // Prevent premature garbage collection (UTF8String returns an inner pointer).
        [applicationName self];
#endif

        // This function is very slow. <rdar://problem/7695589>
        aslresponse response = asl_search(NULL, query);

        asl_free(query);

        // Loop through the query response, grabbing the results into a local store for processing
        if (response != NULL) {

            aslmsg msg = NULL;

            while (NULL != (msg = asl_next(response))) {

                const char *msgTime = asl_get(msg, ASL_KEY_TIME);
                
                if (msgTime == NULL) {
                    continue;
                }
                
                const char *msgText = asl_get(msg, ASL_KEY_MSG);

                if (msgText == NULL) {
                    continue;
                }
                
                const char *msgSender = asl_get(msg, ASL_KEY_SENDER);
                
                if (msgSender == NULL) {
                    msgSender = "";
                }

                // Ensure sufficient capacity to store this line in the local cache
                consoleLinesProcessed++;
                if (consoleLinesProcessed > rawConsoleLinesCapacity) {
                    rawConsoleLinesCapacity *= 3;
                    rawConsoleLines = reallocf(rawConsoleLines, rawConsoleLinesCapacity * sizeof(char **));
                }

                // Add a new entry for this console line
                char **rawLineContents = malloc(3 * sizeof(char *));
                
                size_t length = strlen(msgTime) + 1;
                rawLineContents[FR_CONSOLELOG_TIME] = malloc(length);
                strlcpy(rawLineContents[FR_CONSOLELOG_TIME], msgTime, length);

                length = strlen(msgText) + 1;
                rawLineContents[FR_CONSOLELOG_TEXT] = malloc(length);
                strlcpy(rawLineContents[FR_CONSOLELOG_TEXT], msgText, length);
                
                length = strlen(msgSender) + 1;
                rawLineContents[FR_CONSOLELOG_SENDER] = malloc(length);
                strlcpy(rawLineContents[FR_CONSOLELOG_SENDER], msgSender, length);

                rawConsoleLines[consoleLinesProcessed-1] = rawLineContents;
            }

            asl_release(response);

            // Loop through the console lines in reverse order, converting to NSStrings
            if (consoleLinesProcessed) {
                for (NSInteger i = consoleLinesProcessed - 1; i >= 0; i--) {
                    char **line = rawConsoleLines[i];
                    NSDate *date = [NSDate dateWithTimeIntervalSince1970:atof(line[FR_CONSOLELOG_TIME])];
                    [consoleLines addObject:[NSString stringWithFormat:@"%@ %s: %s\n", [dateFormatter stringFromDate:date], line[FR_CONSOLELOG_SENDER], line[FR_CONSOLELOG_TEXT]]];

                    // If a maximum size > 0 has been provided, respect it and abort if necessary
                    if (maximumSize > 0) {
                        consoleOutputLength += [(NSString *)[consoleLines lastObject] length];
                        if (consoleOutputLength > [maximumSize unsignedIntegerValue]) break;
                    }
                }
            }
        }
    }

    // Convert the console lines array to an output string
    if ([consoleLines count]) {
        for (NSInteger i = [consoleLines count] - 1; i >= 0; i--) {
            [consoleString appendString:[consoleLines objectAtIndex:i]];
        }
    }

    // Free data stores
    for (NSUInteger i = 0; i < consoleLinesProcessed; i++) {
        free(rawConsoleLines[i][FR_CONSOLELOG_SENDER]);
        free(rawConsoleLines[i][FR_CONSOLELOG_TEXT]);
        free(rawConsoleLines[i][FR_CONSOLELOG_TIME]);
        free(rawConsoleLines[i]);
    }
    free(rawConsoleLines);

    return consoleString;
}

@end
