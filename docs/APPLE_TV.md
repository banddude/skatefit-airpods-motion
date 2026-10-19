# SkateFit on Apple TV

Updated 2026-10-19. Native tvOS target plus an iPhone sensor companion. This is not screen mirroring and it does not use a camera.

## Product flow

**Board-mounted AirPod → iPhone running SkateFit → encrypted local network → native Apple TV app**

The iPhone continues to own the AirPod connection, three-pose calibration, raw motion recording and detailed practice history. The TV displays the live calibrated board quaternion, manual/nose-manual hold time, wobble, sideways tilt, session bests and goal progress. Its Manual Runner shares the existing 15 courses and deterministic engine with the phone build.

Use the Apple TV remote to navigate. The native TV interface is landscape and focus-driven, with a large manual-practice display rather than a scaled iPhone layout. An optional controller/remote game mode runs without the phone, explicitly separate from sensor-based training. A board-controlled run waits for real board tilt and pauses if its sensor link goes stale.

## Build identities and release status

| Target | Bundle identifier | Candidate version |
| --- | --- | --- |
| iPhone companion | com.banddude.skatefit.motionlab | 0.1.0 (17) |
| Native Apple TV | com.banddude.skatefit.motionlab.tv | 0.1.0 (1) |
| Local wire protocol | SkateFit TV | 1 |

These are development candidates. **The public iPhone installer remains Beta 16 until build 17 is signed, checked and deliberately deployed.** Beta 16 does not contain the new Apple TV relay. No App Store or TestFlight release is implied by a source build or simulator test. The production SkateFit app and listing remain untouched.

## Once both new builds are installed

1. Keep the board-mounted AirPod paired to the iPhone. Leave the other AirPod in its case or ensure the selected side is the mounted one.
2. Connect iPhone and Apple TV to the same local network. Ethernet for the TV and Wi-Fi for the phone can work if the router permits local communication and Bonjour discovery. Guest-network isolation and VPN policies may block discovery.
3. On the TV choose **Pair iPhone**. The TV advertises a unique local name and displays a ten-character pairing code.
4. On iPhone, tap the Apple TV icon next to game settings, then **Find Apple TV**. Allow Local Network access if prompted. Select the matching TV name and enter its code.
5. On the iPhone start a motion session and complete flat, tail, and nose calibration. The companion view may be left for calibration without ending the connection.
6. Leave SkateFit open and the phone unlocked. The phone's existing active-recording behavior keeps its display awake. Backgrounding or locking the phone ends sharing; return and pair again before continuing.
7. On TV choose Manuals for live balance feedback, or Play → Ride with board AirPod for the game. Actual wheel contact and landed tricks remain unverified by an IMU alone.

For Siri Remote demo controls, focus the game surface: up triggers a manual pop, down a timed nose-manual duck, and Play/Pause pauses/resumes. A supported extended gamepad offers held A/right-trigger manual and B/left-trigger nose manual. Touchscreen-specific controls are not reused on TV.

## Local pairing and data safety

- Discovery: Bonjour service `_skatefit._tcp`, started only after explicit user action. No arbitrary cloud host, account, GPS data or camera access is added.
- Encryption/authentication: Network.framework TLS 1.2 PSK using `TLS_PSK_WITH_AES_128_GCM_SHA256`. A fresh random ten-character code is shown on the TV. Its 32-character alphabet supplies 50 bits of random code space. A per-listener context derives the PSK via HMAC-SHA256. The code is not advertised, logged or persisted.
- One authenticated iPhone per TV listener. Unused codes expire after 120 seconds. Candidate handshakes expire after eight seconds; five failures require a new pairing session. There is no trust-all certificate verifier or plaintext fallback.
- Freshness: the TV issues one outstanding random request nonce at a time. Responses must match the nonce and arrive within 250 ms according to the TV's own clock. The phone snapshot must come from a calibrated sensor sample no older than 200 ms. Duplicate source sequence numbers cannot refresh the live pose.
- If no new accepted frame arrives within 350 ms, the TV clears the pose and pauses board-controlled play. Reconnection requires explicit pairing and resume, rather than silently converting the run to remote controls. A changed iPhone recording session also requires re-arming.
- The protocol is bounded length-prefixed JSON, max 16 KB per complete message. Malformed or oversized messages are rejected rather than truncated. No unbounded stream backlog is used for live controls.
- This timing is a conservative operational cutoff, **not a claim of measured end-to-end motion-to-display latency**. AirPod Bluetooth delay, frame scheduling and real LAN behavior still need hardware validation.

The payload contains calibrated pitch/roll/relative yaw/quaternion, source-session identifier, sample sequence and age, current hold, goal, stability, wobble, session bests and reported sample rate. It contains no coordinates, audio, images, phone contacts or full raw sensor CSV.

## Persistence

The iPhone remains the source of detailed training history and raw motion CSV. The TV retains its own small game career record and backup in app preferences, avoiding reliance on purgeable tvOS cache files. TV and iPhone game careers are not synchronized. Uninstalling either app or clearing device data can remove that app's records; no cloud restore is implemented here.

## Verification commands

The root Swift package is a lightweight macOS test harness for the shared bridge and game logic:

```sh
swift test --jobs 3
```

It includes real encrypted loopback connections with both matching and wrong pairing codes, the actual companion request/response flow, sequence/nonce/timeout checks, frame parsing, and board-start/pause game state. These are not mocked TLS calls.

Native target builds and tests:

```sh
xcodegen generate
xcodebuild -project SkateMotion.xcodeproj -scheme SkateMotionTV \
  -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SkateMotion.xcodeproj -scheme SkateMotionTV \
  -destination 'platform=tvOS Simulator,id=<INSTALLED_SIMULATOR_UDID>' \
  CODE_SIGNING_ALLOWED=NO test
xcodebuild -project SkateMotion.xcodeproj -scheme SkateMotion \
  -destination 'platform=iOS Simulator,id=<INSTALLED_SIMULATOR_UDID>' \
  CODE_SIGNING_ALLOWED=NO test
```

`.github/workflows/apple-platforms.yml` runs both native simulator targets on standard GitHub-hosted macOS runners **only while this repository is public**. It has read-only token permissions, no signing secrets or deployment step, pinned official checkout/artifact actions, and uploads test logs, result bundles and a native TV screenshot. Exact outcomes belong to each CI run, not this checklist.

## Physical Apple TV installation gate

No Apple TV was listed as paired with the development Mac during this implementation. The Mac has a tvOS SDK but no local tvOS simulator runtime, so generic TV builds alone cannot prove native focus behavior or LAN pairing.

For a device build, put the Apple TV into **Settings → Remotes and Devices → Remote App and Devices**, then pair it in Xcode's Devices and Simulators window on the same local network. Register the actual device and create the appropriate tvOS development/ad-hoc profile for the new TV bundle. Do not reuse the iPhone provisioning profile on the TV target. Alternatively, create an App Store Connect record and distribute a separately signed tvOS build through TestFlight after approval.

Do not advertise the existing iPhone Safari install page as a TV installer. It is not one.

## Before calling it ready for real board play

- Confirm both device builds install, launch and retain prior iPhone history.
- Test Bonjour discovery on the actual router and fail clearly on denied Local Network permission.
- Enter correct and incorrect TV pairing codes; prove another unpaired phone cannot drive the board.
- Calibrate the mounted AirPod and confirm nose/tail sign, complete board inversion and live display on the TV.
- Measure real Bluetooth + Wi-Fi latency and packet jitter, including loss, screen lock, app background and reconnection.
- Test Siri Remote focus transitions, supported gamepad controls, pause/resume and the 15-course game on a physical TV.
- Confirm no camera permissions, images, microphone recordings or GPS data are added to the relay.

## Official implementation references

- Apple Network.framework peer-to-peer connection sample: https://developer.apple.com/documentation/network/building-a-custom-peer-to-peer-protocol
- Apple local network privacy guidance: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- Apple tvOS device pairing: https://developer.apple.com/documentation/safari-developer-tools/inspecting-tvos
- Apple Game Controller framework: https://developer.apple.com/documentation/gamecontroller
- Apple UserDefaults: https://developer.apple.com/documentation/foundation/userdefaults
