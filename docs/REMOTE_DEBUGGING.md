# SkateFit Motion Lab: remote development guide

The development console is **publicly accessible over cellular** at:

**https://skatefit-motion-lab.mikejshaffer.workers.dev**

The URL works from a browser, laptop, Oracle machine, automated agent, and iPhone. It is an HTTP API and web app, not a local Wi-Fi socket. The iOS prototype batches sensor samples approximately every 120 readings and saves requests to Application Support before network transfer. Uploads automatically resume after temporary loss of cellular service as long as the app runs again.

**Current device limitation:** AirPods and iPhone hardware behavior requires a real iPhone with the app installed; a simulator can validate app builds, synthetic classification and cloud API but cannot reproduce the skateboard impact and sensor streams.

## Read from anywhere

The public console offers graphs, events, rules and downloads. Automated tools and command-line scripts can use the API directly:

```bash
BASE=https://skatefit-motion-lab.mikejshaffer.workers.dev

# Verify the server is online
curl -fsS "$BASE/health"

# See latest sessions with IDs, timestamps and sample counts
curl -fsS "$BASE/api/sessions" | jq .

# Replace SESSION_ID with a value returned above.
curl -fsS "$BASE/api/sessions/SESSION_ID" | jq .

# Get ALL recorded raw samples. This is a paginated streaming export,
# unlike session detail, which intentionally includes only recent samples.
curl -fL "$BASE/api/sessions/SESSION_ID/export" -o skateboard-motion.csv

# See detector settings currently applied to phones and server replays
curl -fsS "$BASE/api/config" | jq .
```

There is no authentication yet by design. Don't submit private user data.

## Remotely tune detection without reinstall

Numerical thresholds for possible manuals, impacts and rotations are versioned in the backend. The iPhone polls for updates about every 15 seconds while active and uses the most recent validated values.

```bash
BASE=https://skatefit-motion-lab.mikejshaffer.workers.dev

# Read all existing rules before editing them
curl -fsS "$BASE/api/config" | jq .

# Change only the minimum manual duration
curl -fsS -X PUT "$BASE/api/config" \
  -H 'Content-Type: application/json' \
  -d '{"rules":{"minimumManualSeconds":0.7}}' | jq .

# Replay a saved recording under the latest rules
curl -fsS -X POST "$BASE/api/reprocess" \
  -H 'Content-Type: application/json' \
  -d '{"sessionId":"SESSION_ID"}' | jq .
```

Rule updates patch the existing configuration, preserving any values not specified in the request. The dashboard form submits all six fields automatically.

```json
{
  "manualPitchDegrees": 6,
  "minimumManualSeconds": 0.45,
  "impactThresholdG": 1.9,
  "rotationStartRate": 2.6,
  "movementThresholdG": 0.9,
  "maxCandidateSeconds": 1.25
}
```

The native iPhone app is the stable sensor recorder. It never evaluates arbitrary downloaded Swift or JavaScript. For classification experiments requiring brand-new logic, edit `backend/src/detector.js`, run its unit tests, deploy the Worker, and use replay. This does not require reinstalling the iPhone app. Changing native Core Motion code or the SwiftUI recorder **does** require a new signed build.

## Structure of uploaded data

Every upload uses `POST /api/ingest`:

```json
{
  "sessionId": "8EDAB1FE-D13C-43DE-8F5D-EE39EA3B6819",
  "batchId": "38A63D76-63E2-4486-B357-B925ED20C2D8",
  "device": "iPhone SkateFit Motion Lab",
  "preferredSide": "left",
  "calibration": {
    "flat": {"x": 0, "y": 0, "z": -1},
    "tail": {"x": 0.4, "y": 0, "z": -0.9},
    "nose": {"x": -0.4, "y": 0, "z": -0.9}
  },
  "events": [],
  "samples": [
    {
      "source": "headphone",
      "sensorLocation": "left",
      "hostUptime": 1234.125,
      "deviceTimestamp": 1233.9,
      "gravity": {"x": 0.0, "y": 0.0, "z": -1.0},
      "acceleration": {"x": 0.1, "y": -0.1, "z": 0.2},
      "rotationRate": {"x": 0.05, "y": 0, "z": 0.2},
      "pitch": 0,
      "roll": 0,
      "yaw": 0
    }
  ]
}
```

`gravity` is in g (unit length approximately 1), `acceleration` is user acceleration in g, `rotationRate` is rad/s, angles are radians, and times are in seconds. `hostUptime` is the time of callback arrival; `deviceTimestamp` is the Core Motion sensor timestamp. They are not assumed perfectly synchronized across devices. A board-sensor mount may be any orientation because the three calibration poses recover the board's length axis.

The backend de-duplicates uploads by `batchId`. Repeated network retries won't count the same samples twice. With no signal, JSON batches are written to disk first. They remain until the server accepts them. A local CSV is separately available.

## What to check when the classification looks wrong

1. **Do we have board samples?** Check the live console counts and CSV `source` / `sensorLocation`. Incorrect left/right settings or Apple changing the active earbud may cause the app to ignore all board samples for classification. Raw samples remain logged for inspection.
2. **Is calibration valid?** Confirm the flat, tail and nose poses were captured while stationary. Wrong poses, loose tape or rotating the mount after calibration invalidates pitch.
3. **Are we confusing lateral roll with longitudinal pitch?** Calibrated pitch projects gravity onto the board's length axis; the sideways-only tilt unit test prevents one obvious false positive.
4. **Are timing assumptions correct?** Phone-versus-AirPod callback latency may shift timestamps; a landed trick cannot be guaranteed from motion alone.
5. **Is the detector wrong or did the trick actually fail?** Use the ground-truth label editor and independent video, not just the modeled prediction.
6. **Did remote rules actually apply?** The app shows the current rule version. The dashboard shows the current version and last save time. Reprocess saved data after changes.

The session-detail API is intentionally bounded to the most recent samples and candidate events so it can refresh rapidly. The downloadable CSV streams **all** batches, while reprocessing currently uses the latest 150 batches to remain within resource limits.

## Automated testing

For backend logic: `npm test` from the repository root.

For iOS compilation and tests: regenerate the Xcode project with `xcodegen generate`, then use `xcodebuild ... CODE_SIGNING_ALLOWED=NO test` targeting an installed iOS Simulator.

For end-to-end cloud validation: use a clearly named *synthetic* session, POST a small known-tilt sample batch, check idempotent retry, run `/api/reprocess`, and verify expected event plus correctly formatted CSV. Synthetic sessions must never be represented as real skateboarding evidence.

## Important development-only boundary

This backend has been intentionally left **unauthenticated** at the user's request for rapid iteration. Data and rules are public and writable to anyone with its address. It is not a production-ready multiuser service. Add authorization, upload quotas, data protection and retention before broader distribution.
