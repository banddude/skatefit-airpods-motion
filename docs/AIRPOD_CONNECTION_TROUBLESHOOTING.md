# AirPod sensor connection: diagnostic and recovery guide

Updated 2026-10-26. Applies to iPhone Motion Lab and Apple TV companion candidates. No camera or direct tvOS AirPod motion API is used.

## Connection path

**Board-mounted AirPod → iPhone Core Motion → optional encrypted local bridge → SkateFit TV**.

The AirPod must remain connected to the iPhone. Apple TV can use AirPods for audio, but this application does not receive AirPod motion directly from tvOS.

There are three separate states:

1. **Bluetooth audio connected**: the iPhone's audio output picker shows the AirPods. This is not proof of motion tracking.
2. **Headphone Core Motion requested**: Apple's motion manager reports active. This is not proof that the earbud delivered any measurements.
3. **Board sensor truly live**: AirPod readings rise, a known left/right headphone sensor is selected, Board readings rise, and fresh samples pass quality checks. Only this state enables gameplay and TV forwarding.

## Physical checks, in order

1. On the iPhone, go to Settings → Bluetooth. Connect your AirPods **to this iPhone**. If Apple TV suggests moving the AirPods, decline it or switch them back. On Apple TV, Settings → Remotes and Devices → Bluetooth → Suggest Nearby AirPods can be turned off to prevent accidental audio handoff.
2. With the selected earbud mounted securely to the skateboard and the other earbud in its case, disable Automatic Ear Detection in the AirPods settings if available. Choose the mounted side as microphone if that option is offered. Off-ear motion may remain unavailable even with Bluetooth audio connected; the public API does not guarantee board-mounted operation.
3. Keep SkateFit in the foreground and tap Motion Lab → Start session. If Motion & Fitness permission is requested, allow it.
4. Open Fix connection. Use the iPhone AirPods audio route picker and choose the AirPods, then **Wake & Retry AirPod Motion**.
5. Observe **AirPod readings** and **Board readings**. If both rise, the sensor is live. If AirPod readings rise but Board readings stay at zero, stop the session, open Advanced, correct the Board-mounted AirPod side and restart. An unidentified side is refused rather than assumed to be a skateboard sensor.
6. If readings remain at zero after a supported AirPod is confirmed connected, the motion service may not be available off-ear. Check motion permission and ear detection, then retry with the earbud worn briefly to determine whether the hardware exposes head-motion tracking in that configuration. Do not mistake moving the iPhone for board motion.

## Software integrity checks

- Before this repair, Core Motion could display "active" even when zero readings had arrived. The new UI distinguishes a requested manager from a **live sample stream**.
- A new Core Motion epoch ignores callbacks from earlier stopped streams, so one failed request cannot replace the current session's status.
- Automatic retries pause 8, 16, then up to 32 seconds between attempts instead of repeatedly stopping and starting the motion stream. A manually tapped Retry or Wake & Retry is immediate.
- An AirPod disconnect clears the game pose. No phone IMU or unidentified AirPod side is substituted silently. Existing calibration and saved histories are not erased by a retry.
- If the iPhone counts readings but the TV says waiting, the problem is in calibration, pairing, phone foreground state or network freshness, not necessarily Bluetooth. TV board runs are intentionally paused without fresh verified samples.

## What to report if it is still failing

The useful non-sensitive diagnostics are: iPhone AirPod readings count, Board readings count, selected/detected side, whether Sensor available says Yes, Motion permission state, current audio output, and whether the numbers increase when the skateboard is moved. Do not share private device identifiers or pairing codes.

## References

- Apple AirPods switching: https://support.apple.com/guide/airpods/switch-airpods-between-apple-devices-dev228ba3df8/web
- Apple's headphone motion manager: https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager
