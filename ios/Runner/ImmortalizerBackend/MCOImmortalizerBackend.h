// Adapted from ImmortalizerJailed, Copyright (C) 2025 Serge Alagon.
// MCOa integration changes, 2026. SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL MCOImmortalizerSetArmed(BOOL armed);
FOUNDATION_EXPORT void MCOImmortalizerSetBackground(BOOL background);
FOUNDATION_EXPORT BOOL MCOImmortalizerIsArmed(void);
FOUNDATION_EXPORT BOOL MCOImmortalizerAudioRunning(void);
FOUNDATION_EXPORT BOOL MCOImmortalizerHasLegacyInjection(void);
// Pure decision used by the native regression tests; installs no hooks.
FOUNDATION_EXPORT BOOL MCOImmortalizerSuppressesDiff(NSString *description);
FOUNDATION_EXPORT BOOL MCOImmortalizerShouldDeferDiff(NSString *description, BOOL background, BOOL transitioning);
NS_ASSUME_NONNULL_END
