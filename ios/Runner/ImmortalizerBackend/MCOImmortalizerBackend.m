/*
 * Adapted from ImmortalizerJailed main.m (7b2812e).
 * Copyright (C) 2025 Serge Alagon; MCOa integration changes, 2026.
 * SPDX-License-Identifier: GPL-3.0-or-later
 * See LICENSE and NOTICE.md in this directory. No warranty.
 * Scene-hook credit from upstream: @khanhduytran0.
 *
 * Changes: explicit arm/background gates, no constructor or preferences/UI,
 * passthrough when off, bounded deferred scene calls, reusable silent player,
 * event-driven audio recovery, and no notification-delegate swizzling.
 */
#import "MCOImmortalizerBackend.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import <stdbool.h>

static atomic_bool armed;
static atomic_bool physicallyBackground;
static void (*originalScene)(id, SEL, id, id, id, id);
static UIApplicationState (*originalApplicationState)(id, SEL);
static NSMutableArray<void (^)(void)> *deferredScenes;
static BOOL passScenesUntilForeground;
static BOOL sceneBackgroundTransition;
static AVAudioPlayer *player;
static BOOL ownsAudioSession;
static NSString *previousCategory;
static NSString *previousMode;
static AVAudioSessionCategoryOptions previousOptions;

BOOL MCOImmortalizerHasLegacyInjection(void) {
    return NSClassFromString(@"FloatingButtonWindow") != Nil;
}

BOOL MCOImmortalizerIsArmed(void) { return atomic_load(&armed); }
BOOL MCOImmortalizerAudioRunning(void) { return player.isPlaying; }

BOOL MCOImmortalizerSuppressesDiff(NSString *description) {
    for (NSString *marker in @[@"foreground = NotSet", @"foreground = No",
            @"foreground = BSSettingFlagNo", @"foreground = NO",
            @"hostContextIdentifierForSnapshotting = 0",
            @"scenePresenterRenderIdentifierForSnapshotting = 0",
            @"targetOfEventDeferringEnvironments = (empty)", @"FBSceneSnapshotAction:"]) {
        if ([description containsString:marker]) return YES;
    }
    return NO;
}

static BOOL foregroundFlag(NSString *description, BOOL active) {
    if (description.length == 0) return NO;
    // Token boundary matters: "NotSet" also starts with "No".
    NSString *pattern = active
        ? @"\\bforeground\\s*=\\s*(?:Yes|YES|BSSettingFlagYes)(?:[;\\s,}]|$)"
        : @"\\bforeground\\s*=\\s*(?:No|NO|BSSettingFlagNo)(?:[;\\s,}]|$)";
    return [description rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}

BOOL MCOImmortalizerShouldDeferDiff(NSString *description, BOOL background, BOOL transitioning) {
    return (background || transitioning || foregroundFlag(description, NO)) &&
        MCOImmortalizerSuppressesDiff(description);
}

static void flushScenes(void) {
    NSArray<void (^)(void)> *pending = [deferredScenes copy];
    [deferredScenes removeAllObjects];
    for (void (^invoke)(void) in pending) invoke();
}

static void sceneUpdate(id receiver, SEL selector, id scene, id diff, id context, id completion) {
    // Private callbacks on unknown queues stay untouched. All deferred calls
    // originate on main and are replayed on main in their original order.
    NSString *description = [diff description];
    if (NSThread.isMainThread && foregroundFlag(description, YES)) {
        sceneBackgroundTransition = NO;
        flushScenes();
    }
    if (NSThread.isMainThread && atomic_load(&armed) && !passScenesUntilForeground &&
            MCOImmortalizerShouldDeferDiff(description, atomic_load(&physicallyBackground), sceneBackgroundTransition)) {
        sceneBackgroundTransition = YES;
        if (deferredScenes.count < 64) {
            id savedCompletion = [completion copy];
            [deferredScenes addObject:^{
                originalScene(receiver, selector, scene, diff, context, savedCompletion);
            }];
            return;
        }
        // Do not retain an unbounded sequence or lose completion callbacks.
        passScenesUntilForeground = YES;
        flushScenes();
        NSLog(@"[iOSExecution] Scene backlog limit: using system scene updates until foreground");
    }
    originalScene(receiver, selector, scene, diff, context, completion);
}

static UIApplicationState applicationState(id receiver, SEL selector) {
    if (atomic_load(&armed) && atomic_load(&physicallyBackground)) {
        Dl_info info;
        void *address = __builtin_extract_return_addr(__builtin_return_address(0));
        if (dladdr(address, &info) && info.dli_fname) {
            NSString *image = [NSString stringWithUTF8String:info.dli_fname];
            if ([image containsString:@"UserNotifications"] || [image containsString:@"PushKit"]) {
                return UIApplicationStateBackground;
            }
        }
        return UIApplicationStateActive;
    }
    return originalApplicationState(receiver, selector);
}

static NSData *silentWav(void) {
    // One second, PCM16 mono at 8 kHz. No borrowed base64 asset or generator.
    const unsigned char header[44] = {
        'R','I','F','F',0xa4,0x3e,0,0,'W','A','V','E',
        'f','m','t',' ',16,0,0,0,1,0,1,0,0x40,0x1f,0,0,
        0x80,0x3e,0,0,2,0,16,0,'d','a','t','a',0x80,0x3e,0,0
    };
    NSMutableData *data = [NSMutableData dataWithLength:sizeof(header) + 16000];
    [data replaceBytesInRange:NSMakeRange(0, sizeof(header)) withBytes:header];
    return data;
}

static void stopAudio(void) {
    if (!player && !ownsAudioSession) return;
    [player stop];
    player = nil;
    AVAudioSession *session = AVAudioSession.sharedInstance;
    // Do not overwrite a category changed by another app feature meanwhile.
    if (ownsAudioSession && [session.category isEqualToString:AVAudioSessionCategoryPlayback] &&
            [session.mode isEqualToString:AVAudioSessionModeDefault] &&
            session.categoryOptions == AVAudioSessionCategoryOptionMixWithOthers) {
        [session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
        [session setCategory:previousCategory mode:previousMode options:previousOptions error:nil];
    }
    ownsAudioSession = NO;
    previousCategory = nil;
    previousMode = nil;
}

static void startAudio(void) {
    if (!atomic_load(&armed) || !atomic_load(&physicallyBackground) || player.isPlaying) return;
    AVAudioSession *session = AVAudioSession.sharedInstance;
    if (!ownsAudioSession) {
        previousCategory = session.category;
        previousMode = session.mode;
        previousOptions = session.categoryOptions;
    }
    NSError *error = nil;
    if (![session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault
            options:AVAudioSessionCategoryOptionMixWithOthers error:&error]) {
        NSLog(@"[iOSExecution] Audio session unavailable: %@", error.localizedDescription);
        return;
    }
    ownsAudioSession = YES;
    if (![session setActive:YES error:&error]) {
        NSLog(@"[iOSExecution] Audio activation failed: %@", error.localizedDescription);
        stopAudio();
        return;
    }
    if (!player) {
        player = [[AVAudioPlayer alloc] initWithData:silentWav() error:&error];
        player.volume = 0;
        player.numberOfLoops = -1;
    }
    if (![player play]) {
        NSLog(@"[iOSExecution] Silent audio did not start: %@", error.localizedDescription);
        stopAudio();
    }
}

static BOOL installHooks(void) {
    static BOOL installed;
    if (installed) return YES;
    Class target = NSClassFromString(@"FBSWorkspaceScenesClient");
    if (!target) return NO;
    Method scene = class_getInstanceMethod(target,
        NSSelectorFromString(@"sceneID:updateWithSettingsDiff:transitionContext:completion:"));
    Method state = class_getInstanceMethod(UIApplication.class, @selector(applicationState));
    if (!scene || !state || method_getNumberOfArguments(scene) != 6 || method_getNumberOfArguments(state) != 2) return NO;
    deferredScenes = [NSMutableArray array];
    originalScene = (void (*)(id, SEL, id, id, id, id))method_getImplementation(scene);
    originalApplicationState = (UIApplicationState (*)(id, SEL))method_getImplementation(state);
    method_setImplementation(scene, (IMP)sceneUpdate);
    method_setImplementation(state, (IMP)applicationState);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:AVAudioSessionInterruptionNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if ([note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan) {
            [player pause];
        } else if ([note.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue] & AVAudioSessionInterruptionOptionShouldResume) {
            startAudio();
        }
    }];
    [center addObserverForName:AVAudioSessionMediaServicesWereResetNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        player = nil;
        ownsAudioSession = NO;
        startAudio();
    }];
    installed = YES;
    return YES;
}

BOOL MCOImmortalizerSetArmed(BOOL enable) {
    NSCAssert(NSThread.isMainThread, @"Immortalizer control belongs on main");
    if (enable) {
        if (MCOImmortalizerHasLegacyInjection() || !installHooks()) return NO;
        atomic_store(&armed, true);
    } else {
        atomic_store(&armed, false);
        sceneBackgroundTransition = NO;
        stopAudio();
        flushScenes();
    }
    return atomic_load(&armed);
}

void MCOImmortalizerSetBackground(BOOL background) {
    NSCAssert(NSThread.isMainThread, @"Immortalizer control belongs on main");
    atomic_store(&physicallyBackground, background);
    if (background && atomic_load(&armed)) {
        startAudio();
    } else {
        stopAudio();
        passScenesUntilForeground = NO;
        sceneBackgroundTransition = NO;
        flushScenes();
    }
}
