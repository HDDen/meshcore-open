// Adapted from ImmortalizerJailed, Copyright (C) 2025 Serge Alagon.
// MCOa integration changes, 2026. SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL MCOImmortalizerSetArmed(BOOL armed);
FOUNDATION_EXPORT void MCOImmortalizerSetBackground(BOOL background);
// Не включает hooks/hold само по себе; параметры применяются только к нашему audio path.
FOUNDATION_EXPORT BOOL MCOImmortalizerConfigurePower(BOOL leanHooks, BOOL withoutAudio,
    NSTimeInterval bufferDuration, BOOL useOutputSampleRate, NSUInteger loopSeconds);
// Чистая фабрика PCM WAV; nil для неподдерживаемого размера, без audio session.
FOUNDATION_EXPORT NSData * _Nullable MCOImmortalizerCreateSilentWav(NSUInteger sampleRate, NSUInteger seconds);
FOUNDATION_EXPORT BOOL MCOImmortalizerIsArmed(void);
FOUNDATION_EXPORT BOOL MCOImmortalizerAudioRunning(void);
FOUNDATION_EXPORT NSNotificationName const MCOImmortalizerAudioDiagnosticsChanged;
FOUNDATION_EXPORT NSDictionary<NSString *, id> *MCOImmortalizerAudioDiagnostics(void);
FOUNDATION_EXPORT BOOL MCOImmortalizerHasLegacyInjection(void);
// Pure decision used by the native regression tests; installs no hooks.
FOUNDATION_EXPORT BOOL MCOImmortalizerSuppressesDiff(NSString *description);
FOUNDATION_EXPORT BOOL MCOImmortalizerShouldDeferDiff(NSString *description, BOOL background, BOOL transitioning);
NS_ASSUME_NONNULL_END
