# SkateFit Motion Lab beta distribution

The beta is a separate iPhone app with bundle identifier `com.banddude.skatefit.motionlab`, version `0.1.0`, build `1`. It does **not** modify the production SkateFit app.

**Direct-install page:** https://skatefit-motion-lab.mikejshaffer.workers.dev/install

The public page serves an Apple OTA installation manifest, and a Cloudflare Worker streams the signed IPA and existing SkateFit icon from a separate private R2 bucket. The OTA binary is signed specifically for enrolled development iPhones.

## Current status

- Apple bundle identifier registered for `SkateFit Motion Lab`.
- Signing identity is the noninteractive **iPhone Distribution: Michael Shaffer (6D4T7VB2AF)** certificate in the login Keychain.
- Two provisioning profiles are installed: `SkateFit Motion Lab App Store Login` and `SkateFit Motion Lab Ad Hoc Login`.
- Both are registered through App Store Connect API and correspond to the app's bundle identifier.
- The Ad Hoc profile includes the intended test iPhone. Do not commit profiles or signed IPAs to Git.
- Cloudflare bucket `skatefit-motion-betas` holds `ios/SkateFitMotionLab-0.1.0-6.ipa` and `ios/SkateFitMotionLab-icon.png`.
- Worker exposes `/install`, `/beta/manifest.plist`, `/beta/SkateFitMotionLab.ipa`, and `/beta/icon.png`.

## Rebuilding without Apple web login

The Apple Developer API key was sufficient to create the app ID and distribution profiles. App Store Connect app record creation needs separate web-session authentication. **Ad Hoc distribution does not require an App Store Connect app record.**

From the repository root on the signed-in Mac:

```bash
xcodegen generate

xcodebuild -project SkateMotion.xcodeproj -scheme SkateMotion \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /tmp/skatefit-motion-beta.xcarchive \
  'CODE_SIGN_STYLE=Manual' \
  'CODE_SIGN_IDENTITY=iPhone Distribution: Michael Shaffer (6D4T7VB2AF)' \
  'DEVELOPMENT_TEAM=6D4T7VB2AF' \
  'PROVISIONING_PROFILE_SPECIFIER=SkateFit Motion Lab App Store Login' \
  'CODE_SIGNING_ALLOWED=YES' archive
```

Export with a temporary XML `ExportOptions.plist` that includes:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>ad-hoc</string>
<key>signingStyle</key><string>manual</string>
<key>teamID</key><string>6D4T7VB2AF</string>
<key>signingCertificate</key><string>iPhone Distribution: Michael Shaffer (6D4T7VB2AF)</string>
<key>provisioningProfiles</key><dict>
  <key>com.banddude.skatefit.motionlab</key>
  <string>SkateFit Motion Lab Ad Hoc Login</string>
</dict>
</dict></plist>
```

```bash
xcodebuild -exportArchive \
  -archivePath /tmp/skatefit-motion-beta.xcarchive \
  -exportOptionsPlist /tmp/SkateFitExportOptions.plist \
  -exportPath /tmp/skatefit-motion-beta-export
```

Verify the exported IPA by extracting it, checking that `codesign --verify --deep --strict` succeeds on `Payload/SkateMotion.app`, and inspecting `embedded.mobileprovision` with `security cms -D` to verify the intended device is included.

**When shipping a new build:** increment `CFBundleVersion` in **both** `project.yml` and the checked-in `SkateMotion/Info.plist`, regenerate the Xcode project, and rebuild. Verify the actual signed IPA reports the new build number. XcodeGen does not reliably overwrite an already-present tracked Info.plist. Update both the object key and OTA metadata version in `backend/src/beta.js` before redeploying the Worker. Upload the newly exported IPA under the matching key:

```bash
wrangler r2 object put \
  skatefit-motion-betas/ios/SkateFitMotionLab-0.1.0-12.ipa \
  --file /tmp/skatefit-motion-beta-export/SkateMotion.ipa \
  --remote --content-type application/octet-stream

wrangler deploy
```

The command above is illustrative only. The object key, manifest metadata, installer text and IPA version must all match the current build. Build 12 uses \`ios/SkateFitMotionLab-0.1.0-12.ipa\`. Never change the Worker installer to a build unless the new IPA object has been uploaded and its checksum verified.

## TestFlight transition

An App Store Connect record for this new app has **not yet been created**, because the Apple web session is not logged in. The public App Store Connect API does not permit app-record creation. On the Mac, an authorized user can log in with `asc web auth login --apple-id <their-Apple-Account>` using an interactive session and 2FA, then run:

```bash
asc web apps create --name 'SkateFit Motion Lab' \
  --bundle-id 'com.banddude.skatefit.motionlab' \
  --sku 'skatefit-motion-lab-ios-2026' \
  --version '0.1.0' --primary-locale en-US \
  --if-exists skip
```

Once the App Store Connect record exists, export an **app-store** IPA from the signed archive using the App Store provisioning profile and upload it through the authenticated `asc` tooling, then attach it to an internal TestFlight group.

No production SkateFit app or App Store listing should be modified as part of this prototype.

## Field verification

On the target iPhone in Safari, open the install page and tap the install link. Verify that the **SkateFit Motion Lab** icon appears separately from SkateFit. Pair first-generation AirPods Pro, disable automatic ear detection if needed, record stationary movement and the three calibration poses, then perform gentle rolling/manual tests. Check the public cloud dashboard for received board and phone samples. A successful server smoke test with synthetic data is **not** evidence that real off-ear AirPods will track accurately.

This beta has intentionally unauthenticated telemetry and public read access; consult [the privacy notice](../PRIVACY.md) before uploading personal recordings.


## Beta build 2: headphone connection recovery

A live session had over 12,000 phone readings and no AirPod readings. This prevented the first calibration pose from completing. Build 2 now:

- Displays AirPods motion availability, permission, streaming status, detected earbud and sensor sample counts.
- Retries the motion stream automatically if AirPods connect after recording starts.
- Won't start calibration without recent motion from the selected AirPod.
- Times out a stalled calibration and shows progress if AirPod readings arrive.
- Uploads per-session sensor diagnostics to the cloud dashboard.

If using the AirPod outside your ear, disable Automatic Ear Detection and verify Bluetooth reports it **Connected**. Pairing alone is not proof that iOS is delivering headphone motion.

Production D1 migration: \`wrangler d1 execute skatefit-motion-lab --remote --file backend/migrations/0002_sensor_diagnostics.sql\`, applied once.


## Beta build 3: AirPods audio routing and wake

A real iPhone session reported \`headphoneAvailable=true\`, \`headphoneActive=true\`,
\`permission=Authorized\` yet produced **zero headphone sensor callbacks**.
The Kinapod developer documents two device settings needed for off-ear use:
turn off Automatic Ear Detection, **and** set the AirPods microphone to the
specific mounted earbud (not Automatic). If motion stays dormant, play audio
briefly to wake the stream.

Build 3 adds an Apple system audio output picker, a quiet 0.5-second wake tone,
active-output diagnostics and cloud reporting. In Motion Lab:

1. In Settings → Bluetooth → AirPods Pro, disable Automatic Ear Detection and
   choose the mounted earbud in Microphone.
2. Start recording and use the system route picker in the AirPods connection section.
   Select the AirPods audio destination rather than the iPhone speaker.
3. Tap **Play wake tone through selected output**, then watch **AirPod sensor readings**.
4. Only calibrate after that count increases. A motion manager saying "active"
   without readings is not sufficient.

A live hardware test is still required. If the stream remains silent after the
setup, compare behavior in the Kinapod app (which has a verified implementation
using AirPods off ear) before changing skateboard algorithms.


## Beta build 4: simplified skate screen

The main screen is now built for riding instead of debugging. It contains:

- A simple board-sensor connection indicator and one start/stop button.
- A guided three-pose calibration: flat, tail down, nose down. Only the next
  required position has an action, with a visible progress indicator.
- A native SwiftUI side-view skateboard that tilts with calibrated
  longitudinal pitch from the AirPod; positive angle means nose up (manual
  orientation), while negative angle means tail up (nose manual orientation).
- A live numerical angle readout; the phrase manual angle means a position
  only, never a confirmed trick or landing.
- AirPods audio routing and wake controls, cloud status, raw sensor counts,
  CSV export, and the synthetic-data test still exist under Advanced.
- Connection help with audio wake and retry actions available from a sheet.

This build changes the signed iOS app but does not change the telemetry
server API or data schema. Install over the previous beta via the same
/install page. The production SkateFit app is unaffected.


## Beta build 5: automatically select the active board AirPod

Real-session telemetry demonstrated the calibration button bug: the app
persistently assumed **Left** was the mounted earbud, while iOS supplied
**Right** AirPod readings. Thousands of headphone samples were mistakenly
excluded from board input, leaving calibration disabled despite the AirPod
being connected.

Build 5 remembers the selected board-mounted earbud and safely adopts the
first actively streaming AirPod when no board samples or calibration poses
have been captured in the current recording. A right-side stream now
automatically switches from the original left default to **Right**, and
subsequent readings become eligible for calibration immediately.

Once calibration has started or board samples were already accepted, an
unexpected side change is not silently adopted. For tests with both buds
active, confirm that the active stream belongs to the AirPod on the deck.
No hardware or telemetry server changes are needed.


## Beta build 6: persistent full-axis recording and statistics

- Retains the fully working AirPods setup and calibrated pitch/roll plus
  fused-attitude relative yaw. Device-motion quaternion w/x/y/z is persisted
  in the 20-column CSV alongside three accelerometer and gyro axes.
- New native SceneKit board illustrates pitch/roll/yaw in 3D while the
  original side-view skateboard pitch visualization is preserved.
- All board and phone readings are appended incrementally to local CSV,
  avoiding the previous 180,000-sample RAM cap.
- Local Saved Sessions lists current and past recordings with stats,
  event categories, impact spikes, angular travel and shareable raw CSV.
- Completed session summaries are also queued for remote D1 storage and
  shown in the cloud dashboard. This is a summary-only packet supported by
  a safe additive migration:

  wrangler d1 execute skatefit-motion-lab --remote --file backend/migrations/0003_session_stats.sql

  (Already applied to the hosted instance during build 6.)
- Previous telemetry queue contents remain decodable since quaternion and
  summary fields are optional.

These are *sensor observations* and heuristic motion candidates; they are
not skateboarding trick, landing, foot-contact or physical-location proof.
Yaw is relative to flat calibration and may drift over time.

## Beta build 11: Manual Runner

- Five playable world courses with on-screen touch and optional gamepad controls, manual/nose manual challenges, collectibles, checkpoints and saved career data.
- Calibrated AirPods motion mode remains a separate, optional beta feature requiring physical field testing.
- New 120 Hz game simulation and repeatable five-course perfect-run tests.
- Public experimental cloud telemetry is now opt-in, **off by default**. Any packets saved by previous versions stay locally queued until an explicit opt-in.
- This beta is intended for one enrolled test phone and must not be mistaken for App Store readiness.

## Beta build 12: Expanded platform game

- Fifteen individual stages (three per world), new pulsing gates, long chasms, glowing launch pads, score Flow Meter, dynamic upcoming-obstacle cues, extra deck colors and persisted stage selection.
- Motion controller decoupled from diagnostics display throttling: up to 30 Hz game pitch with 0.75-second freshness check and tilt hysteresis.
- Added end-to-end XCUITest flows for normal game use, stage selection and Motion Lab navigation. This is still an ad-hoc beta, not a public App Store release.
- Beta 11 career files are retained. The experimental public Cloudflare telemetry remains opt-in only.
