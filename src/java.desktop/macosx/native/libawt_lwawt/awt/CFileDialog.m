/*
 * Copyright (c) 2011, 2018, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

#import <sys/stat.h>
#import <Cocoa/Cocoa.h>
#import <JavaNativeFoundation/JavaNativeFoundation.h>

#import "CFileDialog.h"
#import "AWTWindow.h"
#import "ThreadUtilities.h"
#import "ApplicationDelegate.h"

#import "java_awt_FileDialog.h"
#import "sun_lwawt_macosx_CFileDialog.h"

@implementation CFileDialog

- (id)initWithOwner:(NSWindow*)owner
              filter:(jboolean)inHasFilter
          fileDialog:(jobject)inDialog
               title:(NSString *)inTitle
           directory:(NSString *)inPath
                file:(NSString *)inFile
                mode:(jint)inMode
        multipleMode:(BOOL)inMultipleMode
      shouldNavigate:(BOOL)inNavigateApps
canChooseDirectories:(BOOL)inChooseDirectories
             withEnv:(JNIEnv*)env;
{
    if (self == [super init]) {
        fOwner = owner;
        [fOwner retain];
        fHasFileFilter = inHasFilter;
        fFileDialog = JNFNewGlobalRef(env, inDialog);
        fDirectory = inPath;
        [fDirectory retain];
        fFile = inFile;
        [fFile retain];
        fTitle = inTitle;
        [fTitle retain];
        fMode = inMode;
        fMultipleMode = inMultipleMode;
        fNavigateApps = inNavigateApps;
        fChooseDirectories = inChooseDirectories;
        fPanelResult = NSCancelButton;
    }

    return self;
}

-(void) disposer {
    if (fFileDialog != NULL) {
        JNIEnv *env = [ThreadUtilities getJNIEnvUncached];
        JNFDeleteGlobalRef(env, fFileDialog);
        fFileDialog = NULL;
    }
}

-(void) dealloc {
    [fDirectory release];
    fDirectory = nil;

    [fFile release];
    fFile = nil;

    [fTitle release];
    fTitle = nil;

    [fURLs release];
    fURLs = nil;

    [fOwner release];
    fOwner = nil;

    [super dealloc];
}

- (void)safeSaveOrLoad {
    NSSavePanel *thePanel = nil;

    /*
     * 8013553: turns off extension hiding for the native file dialog.
     * This way is used because setExtensionHidden(NO) doesn't work
     * as expected.
     */
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:NO forKey:@"NSNavLastUserSetHideExtensionButtonState"];

    if (fMode == java_awt_FileDialog_SAVE) {
        thePanel = [NSSavePanel savePanel];
        [thePanel setAllowsOtherFileTypes:YES];
    } else {
        thePanel = [NSOpenPanel openPanel];
    }
    [thePanel retain];

    if (thePanel != nil) {
        [thePanel setTitle:fTitle];

        if (fNavigateApps) {
            [thePanel setTreatsFilePackagesAsDirectories:YES];
        }

        if (fMode == java_awt_FileDialog_LOAD) {
            NSOpenPanel *openPanel = (NSOpenPanel *)thePanel;
            [openPanel setAllowsMultipleSelection:fMultipleMode];
            [openPanel setCanChooseFiles:YES];
            [openPanel setCanChooseDirectories:YES];
            [openPanel setCanCreateDirectories:YES];
        }

        [thePanel setDelegate:self];

        if (fOwner != nil) {
            if (fDirectory != nil) {
                 [thePanel setDirectoryURL:[NSURL fileURLWithPath:[fDirectory stringByExpandingTildeInPath]]];
            }

            if (fFile != nil) {
                 [thePanel setNameFieldStringValue:fFile];
            }

            CMenuBar *menuBar = nil;
            if (fOwner != nil) {

                // Finds appropriate menubar in our hierarchy,
                AWTWindow *awtWindow = (AWTWindow *)fOwner.delegate;
                while (awtWindow.ownerWindow != nil) {
                    awtWindow = awtWindow.ownerWindow;
                }

                BOOL isDisabled = NO;
                if ([awtWindow.nsWindow isVisible]){
                    menuBar = awtWindow.javaMenuBar;
                    isDisabled = !awtWindow.isEnabled;
                }

                if (menuBar == nil) {
                    menuBar = [[ApplicationDelegate sharedDelegate] defaultMenuBar];
                    isDisabled = NO;
                }

                [CMenuBar activate:menuBar modallyDisabled:isDisabled];
            }

            [thePanel beginSheetModalForWindow:fOwner completionHandler:^(NSInteger result) {

                if (result == NSFileHandlingPanelOKButton) {
                    NSOpenPanel *openPanel = (NSOpenPanel *)thePanel;
                    fURLs = (fMode == java_awt_FileDialog_LOAD)
                         ? [openPanel URLs]
                         : [NSArray arrayWithObject:[openPanel URL]];

                    fPanelResult = NSFileHandlingPanelOKButton;

                    } else {
                        fURLs = [NSArray array];
                    }
                    [fURLs retain];
                    [NSApp stopModal];
                    if (menuBar != nil) {
                        [CMenuBar activate:menuBar modallyDisabled:NO];
                    }
                }
            ];

            [NSApp runModalForWindow:thePanel];
        }
        else
        {
            fPanelResult = [thePanel runModalForDirectory:fDirectory file:fFile];

            if ([self userClickedOK]) {
                if (fMode == java_awt_FileDialog_LOAD) {
                    NSOpenPanel *openPanel = (NSOpenPanel *)thePanel;
                    fURLs = [openPanel URLs];
                } else {
                    fURLs = [NSArray arrayWithObject:[thePanel URL]];
                }
                [fURLs retain];
            }
        }

        [thePanel setDelegate:nil];
    }
    [thePanel release];

    [self disposer];
}

- (BOOL) askFilenameFilter:(NSString *)filename {
    JNIEnv *env = [ThreadUtilities getJNIEnv];
    jstring jString = JNFNormalizedJavaStringForPath(env, filename);

    static JNF_CLASS_CACHE(jc_CFileDialog, "sun/lwawt/macosx/CFileDialog");
    static JNF_MEMBER_CACHE(jm_queryFF, jc_CFileDialog, "queryFilenameFilter", "(Ljava/lang/String;)Z");
    BOOL returnValue = JNFCallBooleanMethod(env, fFileDialog, jm_queryFF, jString); // AWT_THREADING Safe (AWTRunLoopMode)
    (*env)->DeleteLocalRef(env, jString);

    return returnValue;
}

- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url {
    if (!fHasFileFilter) return YES; // no filter, no problem!

    // check if it's not a normal file
    NSNumber *isFile = nil;
    if ([url getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:nil]) {
        if (![isFile boolValue]) return YES; // always show directories and non-file entities (browsing servers/mounts, etc)
    }

    // if in directory-browsing mode, don't offer files
    if ((fMode != java_awt_FileDialog_LOAD) && (fMode != java_awt_FileDialog_SAVE)) {
        return NO;
    }

    // ask the file filter up in Java
    NSString* filePath = (NSString*)CFURLCopyFileSystemPath((CFURLRef)url, kCFURLPOSIXPathStyle);
    BOOL shouldEnableFile = [self askFilenameFilter:filePath];
    [filePath release];
    return shouldEnableFile;
}

- (BOOL) userClickedOK {
    return fPanelResult == NSFileHandlingPanelOKButton;
}

- (NSArray *)URLs {
    return [[fURLs retain] autorelease];
}
@end

/*
 * Class:     sun_lwawt_macosx_CFileDialog
 * Method:    nativeRunFileDialog
 * Signature: (Ljava/lang/String;ILjava/io/FilenameFilter;
 *             Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;
 */
JNIEXPORT jobjectArray JNICALL
Java_sun_lwawt_macosx_CFileDialog_nativeRunFileDialog
(JNIEnv *env, jobject peer, jlong ownerPtr, jstring title, jint mode, jboolean multipleMode,
 jboolean navigateApps, jboolean chooseDirectories, jboolean hasFilter,
 jstring directory, jstring file)
{
    jobjectArray returnValue = NULL;

JNF_COCOA_ENTER(env);
    NSString *dialogTitle = JNFJavaToNSString(env, title);
    if ([dialogTitle length] == 0) {
        dialogTitle = @" ";
    }

    CFileDialog *dialogDelegate = [[CFileDialog alloc] initWithOwner:(NSWindow *)jlong_to_ptr(ownerPtr)
                                                               filter:hasFilter
                                                           fileDialog:peer
                                                                title:dialogTitle
                                                            directory:JNFJavaToNSString(env, directory)
                                                                 file:JNFJavaToNSString(env, file)
                                                                 mode:mode
                                                         multipleMode:multipleMode
                                                       shouldNavigate:navigateApps
                                                 canChooseDirectories:chooseDirectories
                                                              withEnv:env];

    [JNFRunLoop performOnMainThread:@selector(safeSaveOrLoad)
                                 on:dialogDelegate
                         withObject:nil
                      waitUntilDone:YES];

    if ([dialogDelegate userClickedOK]) {
        NSArray *urls = [dialogDelegate URLs];
        jsize count = [urls count];

        static JNF_CLASS_CACHE(jc_String, "java/lang/String");
        returnValue = JNFNewObjectArray(env, &jc_String, count);

        [urls enumerateObjectsUsingBlock:^(id url, NSUInteger index, BOOL *stop) {
            jstring filename = JNFNormalizedJavaStringForPath(env, [url path]);
            (*env)->SetObjectArrayElement(env, returnValue, index, filename);
            (*env)->DeleteLocalRef(env, filename);
        }];
    }

    [dialogDelegate release];
JNF_COCOA_EXIT(env);
    return returnValue;
}
