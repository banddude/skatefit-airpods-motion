# Commercial release acceptance checklist (SkateFit Manual Runner)

Updated 2026-10-13. A successful build or simulator test is not equivalent to a commercially approved App Store game.

## Verified in source and simulator

- [x] Five world courses with deterministic hazards and completion flags.
- [x] A deterministic 120 Hz simulation, tested with 30/60/120 Hz frame input.
- [x] All five worlds finish with zero damage and three stars under a scripted timing trace.
- [x] Manual / nose manual input, jump buffer, duck, invulnerability, collectibles, combos, checkpoints and retry.
- [x] Touch controls, optional supported GameController input, and optional calibrated AirPod pitch mode.
- [x] Motion controller dropout pauses the run; user can continue with touch input.
- [x] On-device progression, best scores, star unlocks, deck colors and backup recovery.
- [x] Distinctive procedural night-city scene, UI navigation, haptics, reduced background motion and high contrast.
- [x] 28 iOS simulator tests (when the latest signed source was last tested) and 13 Node backend tests.
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
