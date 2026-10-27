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
#import <math.h>

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
static atomic_bool leanHooks;
static BOOL withoutAudio, useOutputSampleRate;
static NSTimeInterval requestedBufferDuration;
static NSUInteger loopSeconds = 1;
static NSTimeInterval previousBufferDuration, ownedBufferDuration;
static BOOL ownsBufferPreference;
NSNotificationName const MCOImmortalizerAudioDiagnosticsChanged = @"mco.ios.execution.audioDiagnostics";
static NSUInteger audioStartAttempts, audioPlayStarts, audioCleanupStops;
static NSUInteger audioInterruptions, audioMediaResets, audioRouteChanges, audioFailures;
static NSString *audioEvent = @"initial";

// Read-only hardware/session snapshot: no route names, UIDs, paths or account data.
NSDictionary<NSString *, id> *MCOImmortalizerAudioDiagnostics(void) {
    NSCAssert(NSThread.isMainThread, @"Audio diagnostics belong on main");
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSMutableArray<NSString *> *ports = [NSMutableArray array];
    for (AVAudioSessionPortDescription *port in session.currentRoute.outputs) {
        [ports addObject:port.portType];
    }
    return @{
        @"schema": @1, @"event": audioEvent, @"running": @(player.isPlaying),
        @"backendArmed": @(atomic_load(&armed)),
        @"physicalBackground": @(atomic_load(&physicallyBackground)),
        @"startAttempts": @(audioStartAttempts), @"playStarts": @(audioPlayStarts),
        @"cleanupStops": @(audioCleanupStops), @"interruptions": @(audioInterruptions),
        @"mediaResets": @(audioMediaResets), @"routeChanges": @(audioRouteChanges),
        @"failures": @(audioFailures), @"category": session.category ?: @"unknown",
        @"mode": session.mode ?: @"unknown",
        @"categoryOptions": @(session.categoryOptions), @"outputPortTypes": ports,
        @"sampleRate": @(session.sampleRate), @"preferredSampleRate": @(session.preferredSampleRate),
        @"ioBufferDuration": @(session.IOBufferDuration),
        @"preferredIOBufferDuration": @(session.preferredIOBufferDuration),
        @"playerSampleRate": @(player ? player.format.sampleRate : 0),
        @"playerChannels": @(player ? player.format.channelCount : 0),
        @"playerDuration": @(player.duration), @"playerVolume": @(player.volume)
    };
}

static void publishAudioDiagnostics(NSString *event) {
    audioEvent = event;
    [NSNotificationCenter.defaultCenter postNotificationName:MCOImmortalizerAudioDiagnosticsChanged object:nil];
}

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
    if (atomic_load(&leanHooks)) {
        static NSRegularExpression *yesPattern, *noPattern;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            yesPattern = [NSRegularExpression regularExpressionWithPattern:
                @"\\bforeground\\s*=\\s*(?:Yes|YES|BSSettingFlagYes)(?:[;\\s,}]|$)" options:0 error:nil];
            noPattern = [NSRegularExpression regularExpressionWithPattern:
                @"\\bforeground\\s*=\\s*(?:No|NO|BSSettingFlagNo)(?:[;\\s,}]|$)" options:0 error:nil];
        });
        NSRegularExpression *expression = active ? yesPattern : noPattern;
        return [expression firstMatchInString:description options:0
            range:NSMakeRange(0, description.length)] != nil;
    }
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
    if (atomic_load(&leanHooks) && (!NSThread.isMainThread ||
            (!atomic_load(&armed) && deferredScenes.count == 0))) {
        originalScene(receiver, selector, scene, diff, context, completion);
        return;
    }
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

NSData *MCOImmortalizerCreateSilentWav(NSUInteger sampleRate, NSUInteger seconds) {
    // PCM16 mono, ограничение размера до выделения памяти (максимум 3,84 МБ).
    if (sampleRate < 8000 || sampleRate > 192000 || seconds < 1 || seconds > 10) return nil;
    const uint32_t bytes = (uint32_t)(sampleRate * seconds * 2);
    unsigned char header[44] = {
        'R','I','F','F',0xa4,0x3e,0,0,'W','A','V','E',
        'f','m','t',' ',16,0,0,0,1,0,1,0,0x40,0x1f,0,0,
        0x80,0x3e,0,0,2,0,16,0,'d','a','t','a',0x80,0x3e,0,0
    };
    const uint32_t values[4] = {bytes + 36, (uint32_t)sampleRate, (uint32_t)sampleRate * 2, bytes};
    const NSUInteger offsets[4] = {4, 24, 28, 40};
    for (NSUInteger field = 0; field < 4; field++) {
        for (NSUInteger byte = 0; byte < 4; byte++) header[offsets[field] + byte] = (values[field] >> (byte * 8)) & 0xff;
    }
    NSMutableData *data = [NSMutableData dataWithLength:sizeof(header) + bytes];
    [data replaceBytesInRange:NSMakeRange(0, sizeof(header)) withBytes:header];
    return data;
}

static BOOL ownsCurrentCategory(AVAudioSession *session) {
    return ownsAudioSession && [session.category isEqualToString:AVAudioSessionCategoryPlayback] &&
        [session.mode isEqualToString:AVAudioSessionModeDefault] &&
        session.categoryOptions == AVAudioSessionCategoryOptionMixWithOthers;
}

static void stopAudioWithNotification(BOOL notifyOthers) {
    if (!player && !ownsAudioSession) return;
    audioCleanupStops++;
    [player stop];
    player = nil;
    AVAudioSession *session = AVAudioSession.sharedInstance;
    // Do not overwrite a category changed by another app feature meanwhile.
    if (ownsCurrentCategory(session)) {
        [session setActive:NO withOptions:notifyOthers ? AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation : 0 error:nil];
        // Не стираем preference, которое успела изменить другая функция приложения.
        if (ownsBufferPreference && fabs(session.preferredIOBufferDuration - ownedBufferDuration) < 0.000001 &&
                previousBufferDuration > 0) {
            [session setPreferredIOBufferDuration:previousBufferDuration error:nil];
        }
        [session setCategory:previousCategory mode:previousMode options:previousOptions error:nil];
    }
    ownsBufferPreference = NO;
    ownsAudioSession = NO;
    previousCategory = nil;
    previousMode = nil;
    publishAudioDiagnostics(@"stopped");
}

static void stopAudio(void) { stopAudioWithNotification(YES); }

static NSUInteger currentPlayerRate(void) {
    const double rate = AVAudioSession.sharedInstance.sampleRate;
    return useOutputSampleRate && isfinite(rate) && rate >= 8000 && rate <= 192000
        ? (NSUInteger)llround(rate) : 8000;
}

static void startAudio(void) {
    if (!atomic_load(&armed) || !atomic_load(&physicallyBackground) || withoutAudio || player.isPlaying) return;
    audioStartAttempts++;
    AVAudioSession *session = AVAudioSession.sharedInstance;
    if (!ownsAudioSession) {
        previousCategory = session.category;
        previousMode = session.mode;
        previousOptions = session.categoryOptions;
        previousBufferDuration = session.preferredIOBufferDuration;
    }
    NSError *error = nil;
    if (![session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault
            options:AVAudioSessionCategoryOptionMixWithOthers error:&error]) {
        audioFailures++;
        publishAudioDiagnostics(@"categoryFailed");
        NSLog(@"[iOSExecution] Audio session unavailable: %@", error.localizedDescription);
        return;
    }
    ownsAudioSession = YES;
    if (requestedBufferDuration > 0 && !ownsBufferPreference) {
        if ([session setPreferredIOBufferDuration:requestedBufferDuration error:&error]) {
            ownsBufferPreference = YES;
            ownedBufferDuration = session.preferredIOBufferDuration;
        } else {
            // Непринятое предпочтение не должно отключать прежнее рабочее удержание.
            audioFailures++;
            publishAudioDiagnostics(@"preferencesFailed");
        }
    }
    if (![session setActive:YES error:&error]) {
        audioFailures++;
        publishAudioDiagnostics(@"activationFailed");
        NSLog(@"[iOSExecution] Audio activation failed: %@", error.localizedDescription);
        stopAudio();
        return;
    }
    if (!player) {
        NSData *wav = MCOImmortalizerCreateSilentWav(currentPlayerRate(), loopSeconds);
        if (!wav) {
            audioFailures++;
            publishAudioDiagnostics(@"formatFailed");
            stopAudio();
            return;
        }
        player = [[AVAudioPlayer alloc] initWithData:wav error:&error];
        player.volume = 0;
        player.numberOfLoops = -1;
    }
    if (![player play]) {
        audioFailures++;
        publishAudioDiagnostics(@"playFailed");
        NSLog(@"[iOSExecution] Silent audio did not start: %@", error.localizedDescription);
        stopAudio();
    } else {
        audioPlayStarts++;
        publishAudioDiagnostics(@"started");
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
            audioInterruptions++;
            [player pause];
            publishAudioDiagnostics(@"interruptionBegan");
        } else if ([note.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue] & AVAudioSessionInterruptionOptionShouldResume) {
            publishAudioDiagnostics(@"interruptionEnded");
            startAudio();
        } else {
            publishAudioDiagnostics(@"interruptionEnded");
        }
    }];
    [center addObserverForName:AVAudioSessionMediaServicesWereResetNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        player = nil;
        ownsAudioSession = NO;
        ownsBufferPreference = NO;
        audioMediaResets++;
        publishAudioDiagnostics(@"mediaServicesReset");
        startAudio();
    }];
    [center addObserverForName:AVAudioSessionRouteChangeNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        audioRouteChanges++;
        // Формат меняется только при изменившейся частоте нашего активного выхода.
        if (useOutputSampleRate && player.isPlaying && ownsCurrentCategory(AVAudioSession.sharedInstance) &&
                fabs(player.format.sampleRate - currentPlayerRate()) > 0.5) {
            [player stop];
            player = nil;
            startAudio();
        }
        publishAudioDiagnostics(@"routeChanged");
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

BOOL MCOImmortalizerConfigurePower(BOOL lean, BOOL noAudio, NSTimeInterval buffer,
                                  BOOL outputRate, NSUInteger seconds) {
    NSCAssert(NSThread.isMainThread, @"Immortalizer power belongs on main");
    if (!isfinite(buffer) || buffer < 0 || buffer > 0.2 || seconds < 1 || seconds > 10) return NO;
    const BOOL audioChanged = withoutAudio != noAudio || useOutputSampleRate != outputRate ||
        requestedBufferDuration != buffer || loopSeconds != seconds;
    // При полном отказе от audio освобождаем session с обычным уведомлением.
    if (audioChanged) stopAudioWithNotification(noAudio);
    atomic_store(&leanHooks, lean);
    withoutAudio = noAudio;
    useOutputSampleRate = outputRate;
    requestedBufferDuration = buffer;
    loopSeconds = seconds;
    if (audioChanged) startAudio(); // startAudio проверяет прежние armed/background gates.
    publishAudioDiagnostics(@"powerChanged");
    return YES;
}
