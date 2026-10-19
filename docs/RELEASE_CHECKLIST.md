# Commercial release acceptance checklist (SkateFit Manual Runner)

Updated 2026-10-13. A successful build or simulator test is not equivalent to a commercially approved App Store game.

## Verified in source and simulator

- [x] Fifteen stages across five worlds with deterministic hazards and completion flags.
- [x] A deterministic 120 Hz simulation, tested with 30/60/120 Hz frame input.
- [x] All fifteen stages finish with zero damage and three stars under a scripted timing trace.
- [x] Manual / nose manual input, jump buffer, duck, invulnerability, collectibles, combos, checkpoints and retry.
- [x] Touch controls, optional supported GameController input, and optional calibrated AirPod pitch mode.
- [x] Motion controller dropout pauses the run; user can continue with touch input.
- [x] On-device progression, best scores, star unlocks, deck colors and backup recovery.
- [x] Distinctive procedural night-city scene, UI navigation, haptics, reduced background motion and high contrast.
- [x] 36+ iOS simulator unit tests plus UI navigation tests and 13 Node backend tests.
- [x] Public prototype sensor uploads disabled by default; users must explicitly opt in.

## Required before external beta signoff

- [ ] Run the game on multiple *physical* iPhones, including smallest supported screen, and test tap-and-hold input latency and background/pause/resume.
- [ ] Verify the game scene actually animates at 60 FPS in Instruments under real long-run load; measure memory, thermal and battery draw.
- [ ] Complete human gameplay reviews of all five worlds; identify difficulty spikes, unclear affordances, impossible human timing, touch target issues and checkpoint fairness.
- [ ] Test VoiceOver and Switch Control: tap-and-hold manual/duck mechanics currently require accessible alternatives or documented accommodation.
- [ ] Test Dynamic Type, Reduce Motion, High Contrast and displays with cutouts/safe areas.
- [ ] Physically test board-mounted, off-ear AirPods on supported models: 3-pose calibration, motion latency/jitter, orientation drift, dropouts, earbud battery use and failure behavior.
- [ ] Capture true visual and sensor reference data; do not classify actual skateboarding tricks or landings without ground truth.
- [ ] Inspect the installable beta IPA signature, version, manifest, R2 object and OTA download hash; ensure enrolled phone can install over older build.

## Required before a paid App Store release

- [ ] Decide final product packaging and brand (a separate commercial app vs merging into the existing SkateFit product). Do not alter the existing production SkateFit listing without explicit approval.
- [ ] Prepare final premium game art, animations, level-design variety, sound effects and legally licensed/owned assets; maintain [ASSET_LICENSES.md](../ASSET_LICENSES.md).
- [ ] Replace or secure the public unauthenticated research backend. Provide authentication, retention, data deletion and explicit opt-in if telemetry is kept. Avoid accidentally exposing older experimental recordings.
- [ ] Finalize privacy policy, support URL, age rating, App Store screenshots, promotional text, purchase terms and localization.
- [ ] Choose distribution/pricing, create App Store Connect record, sign an App Store build, upload to TestFlight and secure playtest approval.
- [ ] Verify purchases and restore flows if an in-app purchase is selected; for a one-time paid download, validate storefront pricing and receipt/store policy.
- [ ] Add crash reporting, real-device UI tests and continued integration checks without using costly third-party hosted runners.
- [ ] Resolve all critical crashes, save losses, stuck/progression-blocking courses and purchased-access failures.

**Disposition:** Beta source can be tested. Store submission remains **BLOCKED** until the required checks above are verified with evidence. The motion lab’s signed beta is a separate application from the production SkateFit app.

## Useful commands

\`\`\`bash
npm test
xcodegen generate
xcodebuild -project SkateMotion.xcodeproj -scheme SkateMotion -destination 'platform=iOS Simulator,name=SkateFit Test' CODE_SIGNING_ALLOWED=NO test
\`\`\`


## Beta 13: manual training and full board inversion

- [x] Calibrated complete relative quaternion drives 3D board orientation, including upside-down flips.
- [x] Gravity-only inversion fallback explicitly signals loss of fused attitude.
- [x] Stationary calibration gate rejects shaking, timestamp gaps and sideways nose/tail poses.
- [x] Manual and nose manual pose-hold coach with target, wobble RMS, lateral tilt, per-axis angular rates and local best-session history.
- [x] Optional foreground iPhone GPS speed with explicit permission and no stored coordinates.
- [ ] Physical deck-mounted AirPods confirmation of pitch sign, full inversion, gyro orientation, sample rates and score accuracy.
- [ ] Benchmark tracker against independently recorded video showing wheels, feet and true manual starts/stops.
- [x] No camera or optical tracking; absolute board XYZ remains unavailable.




## Beta 15: Sensor-only training acceptance

- [x] No camera modules, camera usage description, image marker, or camera entry point in source.
- [x] Board-selected AirPod sample integrity, timestamp-order checks and freshness watchdog.
- [x] Qualified manual duration stops on interruptions or out-of-range frames.
- [x] Per-hold technique metrics, failure reasons, saved attempts and next goals.
- [x] Previous saved practice summaries remain readable.
- [ ] Physical mounted-AirPod validation against witnessed manual duration and wobble.
- [ ] Check dropout, reconnection, stale packets, false-positive holds and sustained battery use.
- [ ] Verify installed IPA does not request camera permission.


## Beta 16: AirPod game input acceptance

- [x] Default Auto source selection uses a fresh calibrated AirPod when available, instead of silently forcing Touch.
- [x] Home screen identifies actual runner control source and offers a one-tap Ride With Board option, with calibration route when unavailable.
- [x] An AirPod-controlled run cannot move, award points or spend lives before the first real board tilt.
- [x] Main scene reflects real nose/tail tilt, and in-game 3D skateboard shows current quaternion attitude with sensor rate and action feedback.
- [x] Manual pop and nose-manual duck use dynamic practice angle thresholds and hysteresis; inversion produces neutral input.
- [x] Dropout pauses rather than silently switching control modes; Touch must be chosen explicitly.
- [ ] Test physical board-connected gameplay, input sign, 3D view, packet jitter and sustained rendering performance.
- [ ] Verify game source choice remains correct when old versions had saved Touch mode.


## Native Apple TV candidate and iPhone companion

- [x] Separate tvOS 17+ native application, landscape focus-driven UI, manual dashboard and 15-course game.
- [x] Shared calibrated 3D quaternion board renderer, including upside-down orientation.
- [x] Explicit session-code pairing and encrypted local-network bridge; no direct AirPod-to-TV assumption.
- [x] Real TLS loopback verification for accepted and rejected pairing codes.
- [x] Nonce, monotonic sequence, source-session and stale-frame gates; board runs pause on data loss.
- [x] No camera use and no GPS transmission; existing cloud telemetry settings remain unchanged.
- [x] Source builds declare both platforms and include automated platform tests.
- [ ] Install signed tvOS build on a paired physical Apple TV with the correct tvOS profile.
- [ ] Install the new iPhone companion while preserving existing data; verify LAN permissions and discovery.
- [ ] Validate actual mounted AirPod → iPhone → TV latency, inversion, hold display and dropouts.
- [ ] Approve physical Siri Remote focus, gamepad navigation and all courses on a real TV.
- [ ] Approve TestFlight/App Store packaging; do not treat the iPhone Safari installer as a TV installer.

See [Apple TV implementation and deployment runbook](APPLE_TV.md). CI results are recorded per commit; physical checks remain separate.
