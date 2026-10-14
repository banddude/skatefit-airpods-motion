## Beta 16: Actual board controls for the platform runner

Auto source routing selects a calibrated streaming AirPod on Drop In, and an explicit Ride With Board action overrides old Touch preferences. The game starts motion-controlled runs only after the player physically tilts the deck, uses the calibrated manual angle threshold, animates the runner's deck and an accurate 3D quaternion skateboard, and exposes live action/pose diagnostics. AirPod signal loss pauses the run instead of masking it as touch.

Physical mounted-AirPod game testing and continuous 30 Hz responsiveness validation remain pending.

# SkateFit Manual Runner: commercial production specification

## Product promise
A complete 2.5D platform adventure with a real skateboarding motion controller, optional touch controls, and a polished game that remains fun without an AirPod. Keep the actual game separate from the AirPod diagnostics and motion lab.

## Beta 15: AirPod-only practice integrity

Camera tracking is deliberately excluded. Board-mounted AirPod readings now pass source, sample freshness and integrity checks before contributing to qualified manual and nose-manual holds. The trainer retains each hold's stability, duration, mean tilt, wobble, goal and end reason. Suggested training steps use local personal bests; absolute board XYZ remains unavailable without independently specified hardware.

## Beta 13: manual-first skill development

Manual Balance Coach is now a prominent primary activity alongside the platform game. It has live board-oriented 3D rotation from a calibrated relative quaternion, inversion detection, controllable manual-angle targets, timed holds, lateral wobble, gyro-based correction metrics, local per-session progress, and opt-in foreground iPhone GPS speed. All this is orientation-only evidence, **not confirmed grounded wheel contact or rider foot placement**. Future physical coaching validation should compare each hold and timing against reference video, then prioritize stationary camera optical tracking or dedicated wheel-contact hardware before claiming real trick success. See [spatial tracking and manuals](SPATIAL_TRACKING_AND_MANUALS.md).

## Beta 12 implementation update

- Expanded from one course per world to 15 courses, three per world, retaining beta-11 save identifiers 1...5.
- World 3+ introduces timed neon pulse gates; world 4+ adds launch ramps and long airborne chasms.
- Live directional cues, Flow Meter double-score combos from held balance lines, extra unlockable deck colors and stage selection persistence.
- Board-mounted AirPods controller now uses up to 30 Hz calibrated game pitch instead of ~6 Hz display diagnostics, hysteresis against threshold jitter and a 0.75-second stale sensor watchdog.
- Added XCUI end-to-end regression tests for entering the game, pause/resume, stage locks and the Motion Lab menu.

## Current implementation status (October 2026, beta 11)

**Implemented in source:** Five patterned worlds with a 3-minute first course; deterministic 120 Hz physics with buffered jump/coyote time and hazard overlap windows; manual and nose manual balance-line mechanics; checkpoint retry; collectibles, score/combo/stars; 30/60/120 Hz equivalence testing; automated zero-hit, three-star completion traces for every world; offline touch, optional GameController and calibrated AirPod input with sensor-loss pause; a night-city procedural rider scene; Play/Worlds/Goals/Decks/Profile/Settings navigation; optional system sound feedback and haptics; reduced parallax and high-contrast options; offline saved progress with file backup and corruption recovery; cloud telemetry disabled by default.

**Not complete for a commercial launch:** authored multi-course worlds rather than one course per world; accessibility and sustained performance validation on real devices; commercial model, character animation and custom music/sound production; a true reusable level editor and player run replay recordings; iCloud sync; hardware AirPods gameplay acceptance; an authenticated production telemetry service (the laboratory server is intentionally public); Store/paid distribution, receipt handling, localization and human playtest signoff. All five courses have a deterministic finish trace, but automated playability is not proof of fun, fair novice timing or field readiness.

## Vertical slice: complete before expanding content
1. One 3-minute authored course with a strong start, rising difficulty, checkpoint, finale, and three replay goals. Every obstacle must be beatable with a realistic input timing window.
2. Single source-of-truth fixed-step game simulation, independent from SwiftUI redraws. Add physics collision geometry, input buffering, coyote time where appropriate, replay input recording, pause/background behavior, and deterministic seeded obstacle sequences.
3. Unified input interface for AirPod motion, touch buttons, and controllers. A sensor dropout pauses or switches to accessible touch controls rather than killing the run. Distinguish practice achievements from verified physical movement.
4. Art direction: stylized nighttime skate city with strong foreground silhouette, animated rider, real licensed skateboard asset, multi-layer parallax backgrounds, collectible motion, and tasteful particles. Track attribution and source licenses in ASSET_LICENSES.md.
5. Sound: jump, land, duck, impact, combo, star pickup, and finish. Music and effects must be cleared for commercial use. Provide separate music/SFX volume and haptic toggles.
6. Main UI: Play, Worlds, Challenges, Collection, Profile. Move connection, calibration, telemetry, and debugging to Settings > Motion Controller. Include reduced-motion, high-contrast, and readable text modes.
7. Progression: star grades, time and no-hit goals, XP, cosmetics, unlockable courses, persistent save versioning, recovery from corrupt saves, and cloud sync only after offline behavior is reliable.

## Game content
World 1 Neighborhood: 8-10 fully authored courses. World 2 Concrete: moving obstacles. World 3 Neon: rhythm gates. World 4 Clouds: vertical mechanics. World 5 Impossible Line: mastery courses. Do not multiply unfinished content. Each course needs obstacle timing measurements, collectibles, checkpoints, tutorial cue, replay objectives, and automated completion traces.

## Commercial model
Prefer a premium single purchase with a complete touch-playable game and no ads. Test pricing in the $4.99-$7.99 range before committing. The AirPod is an optional signature controller, not a mandatory purchase or subscription. No pay-to-win progression.

## Release gates
- All backend and iOS tests green, release manifest version matches actual signed IPA, codesign/provisioning verified, checksum of hosted IPA matches signed file.
- Unit tests for jump timing, ducking, collisions, damage invulnerability, combos, progression, checkpoints, and saving. Deterministic simulation replays must pass at 30/60/120 Hz.
- Screenshot review on smallest and largest supported iPhones; VoiceOver, Dynamic Type, Reduce Motion, color contrast and touch targets.
- Physical AirPods Pro testing: actual off-ear readings, mounting orientation, jitter, connection drops, timing latency, calibration recovery, and sensor battery/thermal behavior. Never assume the simulator validates hardware.
- Sustained device performance targets: stable 60 FPS on supported baseline hardware, bounded memory, no persistent thermal throttling, acceptable battery drain, and no lost saves.
- Security: production telemetry authenticated, opt-in collection, retention and deletion controls, privacy disclosures, offline first gameplay, and no public unauthenticated personal data.
- Store: commercial rights verified for every model, sound and texture, purchase restoration, support/privacy pages, crash reporting, and TestFlight playtest signoff.
- No known critical crashes, progression blockers, purchase errors or data loss. Do not claim zero bugs.

## Priorities
P0: deterministic physics/collisions and input abstraction; P1: premium vertical slice; P2: progression/save robustness; P3: worlds/content; P4: commerce and launch hardening. Never ship unfinished systems just to increase the build number.
