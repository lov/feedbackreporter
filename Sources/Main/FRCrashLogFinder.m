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

#import "FRCrashLogFinder.h"
#import "FRApplication.h"

@implementation FRCrashLogFinder

+ (BOOL)file:(NSString*)path isNewerThan:(nullable NSDate*)date
{
    assert(path);

    NSFileManager *fileManager = [NSFileManager defaultManager];

    if (![fileManager fileExistsAtPath:path]) {
        return NO;
    }

    if (!date) {
        return YES;
    }

    NSError* error = nil;
    NSDate* fileDate = [[fileManager attributesOfItemAtPath:path error:&error] fileModificationDate];
    if (!fileDate) {
        NSLog(@"Error while fetching file attributes: %@", [error localizedDescription]);
    }

    if ([date compare:fileDate] == NSOrderedDescending) {
        return NO;
    }
    
    return YES;
}

+ (NSArray*) findCrashLogsSince:(nullable NSDate*)date
{
    NSMutableArray *files = [NSMutableArray array];

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSArray *libraryDirectories = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSLocalDomainMask|NSUserDomainMask, NO);

    NSUInteger i = [libraryDirectories count];
    while (i--) {
        NSString* libraryDirectory = [libraryDirectories objectAtIndex:i];

        NSDirectoryEnumerator *enumerator = nil;
        NSString *file = nil;
        
        NSString* logDir2 = @"Logs/DiagnosticReports/";
        logDir2 = [[libraryDirectory stringByAppendingPathComponent:logDir2] stringByExpandingTildeInPath];

         NSLog(@"Searching for crash files at %@", logDir2);

        if ([fileManager fileExistsAtPath:logDir2]) {

            enumerator = [fileManager enumeratorAtPath:logDir2];
            while ((file = [enumerator nextObject])) {

                // NSLog(@"Checking crash file %@", file);
                
                NSString* expectedPrefix = [FRApplication applicationName];
                if (([[file pathExtension] isEqualToString:@"crash"] || [[file pathExtension] isEqualToString:@"ips"]) && [[file stringByDeletingPathExtension] hasPrefix:expectedPrefix]) {

                    file = [[logDir2 stringByAppendingPathComponent:file] stringByExpandingTildeInPath];

                    if ([self file:file isNewerThan:date]) {

                        // NSLog(@"Found crash file %@", file);

                        [files addObject:file];
                    }
                }
            }
        }
    }
    
    return files;
}

@end
