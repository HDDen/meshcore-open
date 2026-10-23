# ImmortalizerJailed backend adapted for MCOa

Source: https://github.com/sergealagon/ImmortalizerJailed
Snapshot: 7b2812e, inspected 2026-10-23.
Copyright (C) 2025 Serge Alagon. Scene-hook credit: @khanhduytran0.
License: GNU GPL version 3 or (at your option) any later version; see LICENSE.

MCOa changes (2026): separated backend interface; explicit eligibility/manual/
physical-background gates; no constructor, global delegate hook or shared
upstream preference; bounded replay of main-thread scene updates; synthetic WAV
and reusable player, event-driven interruption recovery, release on foreground.
Floating-window implementation and policy are separate from this backend.

This port uses private iOS APIs and is provided without warranty. Distribution
conditions for the combined application are the distributor's responsibility;
keeping this backend in a separate directory does not change its license.
