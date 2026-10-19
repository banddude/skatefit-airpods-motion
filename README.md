# Native Apple TV candidate + iPhone sensor companion

The new **SkateFit TV** target runs natively on Apple TV with a landscape manual-balance dashboard, full 3D board rotation, the existing 15-course runner, and Siri Remote / gamepad navigation. Your **board-mounted AirPod stays connected to the iPhone**, which shares calibrated motion over an explicitly paired, encrypted local network link. **No camera tracking.**

The candidate versions are **iPhone 0.1.0 (17)** and **tvOS 0.1.0 (1)**. They require both updated apps. This source change is **not a public TV installation or App Store release**. The existing iPhone installer still serves Beta 16 until a new signed companion release is verified and deployed; it is not an Apple TV installer.

Manual practice history and raw motion recordings stay on iPhone. TV game progress is separate. Loss of fresh board data pauses board-controlled play instead of letting stale input advance a score.

See [Apple TV setup, architecture and release checks](docs/APPLE_TV.md). Physical Apple TV installation, local-network pairing and board gameplay remain device acceptance gates.

---

# Beta 16: AirPod controls now drive the Manual Runner game

Registered iPhone beta: https://skatefit-motion-lab.mikejshaffer.workers.dev/install

Fixed the disconnect between training and the game. Previous releases opened the runner in Touch mode by default even with a calibrated board AirPod actively recording. The platform also scrolled and collected points without requiring physical board movement.

The new default control mode is Auto. When the selected board-mounted AirPod has a calibrated, fresh motion stream, DROP IN opens a real AirPod-controlled run. RIDE WITH BOARD offers a direct one-tap choice even when old settings saved Touch. When no board is ready, the game clearly says so and links to Motion Lab calibration.

AirPod runs initially remain stationary, with no progress, scoring or lost lives until the actual board is tilted. Nose up triggers a manual pop and tail up triggers a nose-manual duck. Thresholds follow the Manual Balance Coach target/tolerance with sensor hysteresis.

The runner's skateboard graphics and an embedded native 3D board now follow the real calibrated AirPod pose, including inversion when fused quaternion attitude is available. Pitch, roll, sensor status and the active game action are visibly displayed. An upside-down or edge-on board cannot falsely trigger a jump. AirPod signal loss pauses gameplay rather than silently switching to Touch.

Touch/gamepad remain fully playable, clearly labeled and offline. Camera-free tracking is unchanged. AirPods do not prove wheel contact, absolute board XYZ, or a successfully landed trick. Tests can verify game routing and simulated response; true board-mounted hardware behavior needs physical testing.

---

# Beta 15: AirPod sensor-only manual training

**Latest enrolled-device beta:** https://skatefit-motion-lab.mikejshaffer.workers.dev/install

Camera tracking and camera permission are removed. The trainer uses the securely mounted AirPod's gravity, gyroscope, acceleration, timestamps and calibrated 360-degree attitude, plus optional iPhone GPS for outdoor speed. AirPod-only XYZ location and board jump height are **not reliably measurable**; the app does not fabricate them.

**More accurate balance scoring:** Only fresh frames from the selected board AirPod qualify. Out-of-order, duplicate and implausible readings are rejected. Dropouts and even one flat or unstable frame break a candidate hold instead of inflating its duration. The new quality display shows actual sample rate, gaps, and rejected frames.

**Practice progression:** Each qualified manual or nose-manual attempt is recorded locally with duration, mean tilt, RMS pitch wobble, sideways tilt, average stability, goal, and reason it ended. Suggested next milestones follow personal bests. Old Beta 13 practice records remain readable and no locally saved records are erased.

The platform game remains intact with all 15 stages. Optional research uploads are still OFF by default. Without wheel/foot-contact sensors, these are **orientation-qualified candidate holds**, not independently verified landed skateboard tricks.

[Training limitations and sensor validation](docs/SPATIAL_TRACKING_AND_MANUALS.md) | [Release checks](docs/RELEASE_CHECKLIST.md)

---

# Manual Balance Coach beta 13: full board orientation and real practice goals

**Latest enrolled-device iPhone beta:** https://skatefit-motion-lab.mikejshaffer.workers.dev/install

**Manual training is now featured first on the home screen.** Mount and calibrate one AirPod (shaky or sideways calibration poses now fail closed), then use the dedicated coach for manual and nose-manual target angle, angle tolerance, balance-hold goals, duration, RMS pitch wobble, sideways tilt, per-axis angular-rate corrections, stability score, haptic milestone feedback, and saved session personal bests. Data is based on calibrated board pose and never claims to prove both feet on deck or grounded wheel contact.

**Full 3D orientation:** SceneKit now receives a calibration-aligned fused quaternion rather than multiple ambiguous Euler rotations. The board can roll all the way through 180° upside-down and 360°, and the app labels wheels-down, edge-on and grip-down. When fused attitude is unavailable or disagrees with measured gravity, a gravity-only orientation fallback is clearly labeled; true flip axis and heading can then be unknown. All gyro/acceleration/gravity axes and the quaternion are still retained in raw CSV.

**Optional GPS speed:** You may explicitly enable foreground Core Location in the coach to display approximate outdoor iPhone travel speed and accuracy. No GPS coordinates/routes are saved or uploaded. GPS cannot show board X/Y/Z or airborne height, and AirPods IMU-only acceleration cannot be integrated into reliable 3D position.

The 15-stage Manual Runner game, offline career saves, telemetry opt-in and separate Motion Lab remain available. See [Spatial Tracking and Manuals](docs/SPATIAL_TRACKING_AND_MANUALS.md) for physics, capability boundaries, camera/optical tracking alternatives and release testing. Real mounted-AirPod hardware behavior, ride coaching scores, and commercial readiness still require independent physical testing.

---

# Manual Runner Beta 12: expanded game and more responsive motion input

**Install beta 12 on the registered test iPhone:** https://skatefit-motion-lab.mikejshaffer.workers.dev/install

The built-in Manual Runner now has **15 playable courses across five themed worlds**, including neon pulse gates, automatic launch ramps, longer chasms, more distinct stage pacing and names, and a Flow Meter that rewards properly held manual/nose-manual balance lines with double-score combos. An on-screen obstacle cue tells you whether to pop, duck, hold a balance line, or ride a ramp. Additional unlockable decks and a three-star completion goal reward repeat play. Existing beta 11 saves and unlocked worlds remain usable.

The board-mounted AirPods controller now uses a separate faster gameplay pitch stream (up to 30 Hz), directional hysteresis, and a 0.75-second freshness watchdog. **Actual AirPods off-ear hardware performance remains unverified**. The game also works completely offline with touch and supported gamepad controls, and public experimental telemetry remains **off by default**.

The project has 15-stage simulation coverage, save-compatibility tests, and Xcode UI smoke tests. Commercial release is still blocked on hardware playtesting, external accessibility/performance testing, legal asset provenance and production distribution/security. See [Release Checklist](docs/RELEASE_CHECKLIST.md).

---

# Manual Runner Beta 11: October 2026

The SkateFit motion prototype now includes a **standalone, offline-first manual/nose-manual platform game**. It is playable with on-screen controls or supported gamepads; calibrated AirPods motion control is optional. There are five authored worlds (the first is approximately 3 minutes), jumps, ducking, manual and nose-manual balance lines, checkpoints, pickups, star ratings, an offline career save with backup recovery, cosmetics, challenges, haptics, and high-contrast/reduced-motion options.

The game screen is the default and the experimental motion recorder has moved to **Settings → Open Motion Lab**. Physical-AirPods hardware behavior remains **unverified**. The game's controls do not prove landed real skateboard tricks. **Public Cloudflare raw-data uploads are now OFF by default** and require explicit consent inside Motion Lab's Advanced panel. Previously collected public beta data is not deleted by this change.

[Install the ad-hoc iPhone beta](https://skatefit-motion-lab.mikejshaffer.workers.dev/install) (registered test device only) · [Commercial acceptance checklist](docs/RELEASE_CHECKLIST.md) · [Asset provenance](ASSET_LICENSES.md)

**Status: feature-complete prototype, not commercially releasable.** 28 iOS simulator tests and 13 backend tests pass in the current development branch. Still needed for commercial release: actual AirPods field tests, accessibility/performance validation on multiple physical iPhones, hardened or removed public telemetry, commercial art/audio chain-of-title, app-store packaging and store review.

---

## Build 6: 3-axis motion and permanent skate sessions

**Latest signed iPhone beta:** https://skatefit-motion-lab.mikejshaffer.workers.dev/install

After the three-pose board calibration, SkateFit Motion Lab records
**pitch, roll, and relative yaw** from AirPods gravity and fused attitude
quaternions, with an interactive-looking (but noninteractive) native 3D
skateboard that follows the measured orientation. All three raw gyro
axes and all three acceleration axes are recorded alongside quaternion
w/x/y/z values.

Skating sessions now use incremental on-device CSV writing rather than
an in-memory sample cap. On Stop, the app saves session duration, board
and phone sample counts, acceleration and angular-velocity peaks,
three-axis angular travel, impact spikes, manual-angle hold time, and
possible trick detection counts to permanent local session history.
Raw CSV and JSON summaries remain accessible in Saved Sessions after
relaunch. Completed statistics also upload to the cloud dashboard using
the existing offline retry queue.

**Interpretation:** Yaw is relative to calibration and may drift. Angular
travel and impulse spikes do NOT prove trick names, actual landings,
on-board foot placement, position, or physical distance traveled. All
trick counts are explicitly marked *possible*.

# SkateFit Motion Lab

**Public, experimental iPhone + AirPods Pro skateboard motion recorder and development console.**

This is a **working SwiftUI prototype** plus a **Cloudflare Worker / D1 telemetry backend**, built as a tool for developing trick recognition. It is not a validated trick detector.

**Live dashboard:** https://skatefit-motion-lab.mikejshaffer.workers.dev

**Latest iPhone beta (build 5):** https://skatefit-motion-lab.mikejshaffer.workers.dev/install

Build 5 fixes a mismatch found in live telemetry: actual **right** AirPod
motion was being discarded because the recorder defaulted to **left**.
During initial connection, the app now follows the active earbud (if no
board motion/calibration has been accepted yet) and remembers the chosen
side across sessions. Once calibration is underway, it will not silently
switch sensors.


**Install latest iPhone beta (build 4):**
https://skatefit-motion-lab.mikejshaffer.workers.dev/install

The main screen now uses a live, native SwiftUI skateboard side view
that follows calibrated AirPod pitch. Setup is a three-step guided
calibration (flat, tail, nose). One Start/Stop button controls the session,
while all developer diagnostics are under Advanced. Board angle alone
does not confirm a landed manual or trick.


**Beta privacy:** [Privacy and Data Policy](PRIVACY.md)

**Remote diagnostics, API examples and calibration troubleshooting:** [Remote Debugging Guide](docs/REMOTE_DEBUGGING.md).

## Features implemented

- Simultaneous motion sampling from the AirPods with `CMHeadphoneMotionManager` and iPhone with `CMMotionManager`.
- Timestamped acceleration, gravity, rotation rate and sensor location, retained separately for each stream.
- Pick the board-mounted left or right AirPod; samples from the opposite earbud are logged but excluded from trick detection.
- Three-position calibration: **tail on ground, nose on ground, four wheels down**.
- Calibrated board pitch and sideways-tilt rejection for possible manuals / nose manuals.
- Experimental candidate flip, shove, combination, and ollie/pop detection.
- Local CSV export and remote live session viewing.
- Over-cellular uploads to Cloudflare with a persistent, disk-backed queue for service interruptions.
- Web console with separate board acceleration, board pitch, board rotation and phone acceleration graphs, live numeric threshold tuning, ground-truth labels, event replay and full raw CSV export.
- Remote rule updates fetched by the iPhone approximately every 15 seconds while the app is active.

**Not verified:** real off-ear AirPods tracking, accuracy at skateboard impacts, trick identification or whether a trick was actually landed. The app and server distinguish candidates from observations.



## Install the signed iPhone beta

**Open [SkateFit Motion Lab's install page](https://skatefit-motion-lab.mikejshaffer.workers.dev/install) in Safari on the registered iPhone.** Tap Install Beta and accept the iOS confirmation. This is a separately signed, Ad Hoc distribution, not a TestFlight build. It does not modify the existing SkateFit application.

[Beta distribution and signing instructions](docs/BETA_DISTRIBUTION.md).

The direct-install IPA is served from a separate Cloudflare R2 bucket through the Worker. The signed binary is deliberately not committed to the public source repository. An Ad Hoc provisioning profile restricts installation to enrolled devices; the binary may reveal its enrolled device identifiers to anyone who downloads it. This temporary distribution is intentionally public for rapid testing.

**For TestFlight** a separate App Store Connect app record is still required. The repository can be archived and exported with signing certificates, but creating the record requires a logged-in Apple web session. Apple API-key authentication alone cannot create an app record via the public App Store Connect API.

## Build on a Mac

Requirements: Xcode, XcodeGen, iOS 17+ and AirPods Pro with motion support.

```sh
brew install xcodegen
git clone https://github.com/banddude/skatefit-airpods-motion.git
cd skatefit-airpods-motion
xcodegen generate
open SkateMotion.xcodeproj
```

For simulator testing (adjust the destination to match your Simulator):

```sh
xcodebuild -project SkateMotion.xcodeproj -scheme SkateMotion \
  -destination 'platform=iOS Simulator,name=SkateFit Test' \
  CODE_SIGNING_ALLOWED=NO test
```

To install on a physical iPhone, choose the connected iPhone and an Apple development **Team** in Xcode's Signing & Capabilities, enable automatic signing, and Run. This repo isn't yet distributed via TestFlight. No credentials are committed.

## AirPods troubleshooting (beta build 2)

If the first **four wheels down** calibration step keeps collecting without finishing, confirm the app is actually receiving **AirPods motion**, not merely iPhone motion. The first real test session showed over **12,000 iPhone readings and zero AirPod readings**, so it could not calibrate. This is not evidence the board position was incorrect.

Build **0.1.0 (2)** displays headphone motion availability, authorization, active stream, selected/detected side and reading counts. It retries when headphones connect later, times out stale calibration, and sends those health indicators to the live cloud dashboard. Use **Retry AirPods connection** while recording after connecting AirPods under Settings → Bluetooth. Disable Automatic Ear Detection for off-ear motion tests. Press a calibration pose only after the **AirPod sensor readings** counter begins increasing.

See [the full beta installation notes](docs/BETA_DISTRIBUTION.md) for signed OTA distribution and updating the app.

## Field-test procedure

1. Pair your AirPods Pro; for early tests leave one **board-mounted** AirPod outside its case and the other in its case. Disable Automatic Ear Detection if needed. Apple's API reports motion for only one active earbud at a time.
2. Secure the mounted AirPod in a rigid padded taped holder, away from board impacts and your feet. The AirPod can be damaged or lost.
3. Launch the app on the iPhone, select the board-mounted side, and start recording. Keep the app in the **foreground**. Recording disables automatic idle locking, but iOS can suspend sensors if you manually lock the phone or switch apps.
4. Hold each calibration pose stationary for 1.5 seconds. Verify the app reports a valid calibration and nonzero board readings.
5. Try rolling, stopping, lifting the nose/tail, manuals and nose manuals. Then try small ollies, pops and flips. Record reference video for labeling what really happened.
6. Tap Stop to export a local CSV. With cellular service, readings appear at the [live dashboard](https://skatefit-motion-lab.mikejshaffer.workers.dev). Offline batches are stored and retried later.
7. From any browser, edit rule thresholds, **Reprocess recent samples**, add ground-truth labels and download the full session CSV.

The iPhone sensor callback arrival time and device timestamp are both saved. They are **not perfectly synchronized** between devices.

## Architecture

```text
AirPod sensor -> Core Motion --+
                               +-> iPhone: calibration, candidate detector
Pocket iPhone -> Core Motion --+        | local CSV
                                        | disk-backed upload queue
                                        v
                                  Cellular / HTTPS
                                        |
                                  Cloudflare Worker
                                   /    |       \
                             D1 batches rules  browser dashboard
                                   |             |
                                event replay <- labels / threshold edits
```

Native motion capture, calibration and UI code changes require rebuilding the app. **Detection thresholds** and **server-side replay code** can change without reinstalling. Remote settings are validated numerical data, not remotely executable native code.

Default parameters:

| Rule | Value | Use |
|---|---:|---|
| `manualPitchDegrees` | 6 | Minimum nose/tail tilt |
| `minimumManualSeconds` | 0.45 | Manual candidate hold duration |
| `impactThresholdG` | 1.9 | Landing-impact candidate |
| `rotationStartRate` | 2.6 | Rotation candidate threshold in rad/s |
| `movementThresholdG` | 0.9 | Acceleration candidate threshold |
| `maxCandidateSeconds` | 1.25 | Candidate window maximum |

**Limitations:** The event classifier is heuristic, confidence numbers are not statistically calibrated, actual feet-on-board and airtime cannot be proved using the AirPod alone, and multi-axis fast rotations may be under-sampled. Always retain the video/human ground-truth labels.

## Backend

Worker endpoint: https://skatefit-motion-lab.mikejshaffer.workers.dev
D1 database: `skatefit-motion-lab` (separate from OfficeAdmin).

Once Wrangler is authenticated to the correct Cloudflare account:

```sh
npm test
wrangler d1 execute skatefit-motion-lab --remote --file backend/schema.sql
wrangler deploy
```

The database schema is additive on an empty database; existing tables are not dropped.

The service provides:

- `GET /health` service heartbeat
- `GET /api/config` and `PUT /api/config` for live detection thresholds
- `POST /api/ingest` for idempotent batches of motion samples
- `GET /api/sessions` for recent sessions
- `GET /api/sessions/{id}` for recent samples, events and labels
- `GET /api/sessions/{id}/export` for **streaming all** raw readings to CSV
- `POST /api/reprocess` to reclassify the most recent **150 batches** in a session
- `POST /api/labels` to save human decisions separately from predictions

Batch payloads contain `sessionId`, `batchId`, `preferredSide`, `samples`, `events` and optional three-pose `calibration`. iOS sends up to 120 readings per upload, persisted before transmitting. The server de-duplicates batch IDs and preserves raw data separately from predictions. Replay currently uses the latest 150 batches for bounded execution; raw CSV export isn't truncated.

## Testing

```sh
npm test
node --check backend/src/worker.js
xcodegen generate
xcodebuild -project SkateMotion.xcodeproj -scheme SkateMotion \
  -destination 'platform=iOS Simulator,name=SkateFit Test' \
  CODE_SIGNING_ALLOWED=NO test
```

The test suite covers manuals/nose manuals, board pitch calibration, sideways tilt, short wobbles, filter of phone-only data, CSV fields and server replay under edited thresholds. The deployed API was smoke tested with a clearly labeled **synthetic** session. None of these tests substitute for actual AirPods hardware testing.

## File layout

- `SkateMotion/Models/`: sensor samples, calibration, candidate detector.
- `SkateMotion/Services/MotionStore.swift`: iPhone/AirPod motion streams.
- `SkateMotion/Services/TelemetryUploader.swift`: cellular retry queue, remote rules.
- `SkateMotion/Views/`: recorder and calibration UI.
- `SkateMotionTests/`: iOS unit tests.
- `backend/src/worker.js`: API and persistent storage.
- `backend/src/detector.js`: replay classifier.
- `backend/src/dashboard.js`: web console.
- `backend/schema.sql`: D1 schema.
- `backend/test/`: backend tests.
- `project.yml`: reproducible Xcode project generated with XcodeGen.

## Privacy

**This is intentionally a publicly accessible, unauthenticated development service, as requested.** Anyone can read or overwrite experiment rules, view sensor data, add labels and upload batches. Do **not** upload sensitive personal information, credentials or location data. Add authentication, throttling, quotas and retention controls before using it with other users or calling it production-ready.

## License

MIT. See [LICENSE](LICENSE).


### AirPod sensor wake-up (build 3)

If the AirPod manager reports **available, authorized, active** but the AirPod
sample count remains zero, switch off **Automatic Ear Detection**, select the
**mounted earbud under Bluetooth → AirPods → Microphone**, and choose AirPods as
the audio output with the in-app picker. The app now includes a short wake tone
and reports the selected audio destination to the live dashboard. This matches
the off-ear setup documented by [Kinapod Disc](https://kinapod.com/disk/faq/).
