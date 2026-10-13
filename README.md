# SkateFit Motion Lab

**Public, experimental iPhone + AirPods Pro skateboard motion recorder and development console.**

This is a **working SwiftUI prototype** plus a **Cloudflare Worker / D1 telemetry backend**, built as a tool for developing trick recognition. It is not a validated trick detector.

**Live dashboard:** https://skatefit-motion-lab.mikejshaffer.workers.dev

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
