# SkateFit Manual Runner: commercial production specification

## Product promise
A complete 2.5D platform adventure with a real skateboarding motion controller, optional touch controls, and a polished game that remains fun without an AirPod. Keep the actual game separate from the AirPod diagnostics and motion lab.

## Current implementation status
Five simple courses, a SwiftUI-drawn playfield, jump/duck input, basic hazards, score, lives, and persistent unlocks exist. This is NOT a production-ready game. There is no shipped character animation system, authored level editor, licensed commercial art/audio pack, proper controller compatibility testing, accessibility certification, purchase entitlement implementation, or real-AirPod gameplay acceptance. The latest audit fixed a stale backend release test and added deterministic runner tests; neither implies a commercial release is ready.

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
