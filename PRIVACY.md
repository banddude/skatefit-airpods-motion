# SkateFit Motion Lab beta: data and privacy

**Last updated: October 14, 2026.**

SkateFit Motion Lab is a public, experimental research prototype that uses the iPhone's motion sensors and compatible AirPods to investigate skateboard trick recognition.

## Data collected

During recording, the app collects accelerometer, gravity, angular-velocity, sensor-orientation and timestamp readings from the iPhone and connected AirPods. It also records calibration positions, candidate motion events and any experimental labels added in the web dashboard. Each recording receives a random session identifier.

The app does **not** intentionally collect microphone recordings, photos, contact lists or account credentials. Optional iPhone GPS speed in Manual Balance Coach asks for While Using App location permission and reads location only transiently to calculate speed and quality; the app does not save, export or upload GPS coordinates or routes. Location services are off until you explicitly enable them and stop when the coach screen closes. It does not ask for user login. It does transmit sensor and timestamp data to Cloudflare through the public developer API only if you explicitly enable the cloud-sync switch (off by default).

## Public experimental system

This prototype deliberately has **no authentication** on its cloud development console. Recorded sessions, raw readings, event labels and detector settings are available to anyone who knows or discovers the dashboard URL. Visitors can also edit the experiment settings and upload data. Do not use this service for sensitive or identifying information.

Raw sensor readings are stored in a Cloudflare D1 database, which is used for reviewing sessions and developing classifiers. An installable iOS beta is hosted separately in Cloudflare R2. This Ad Hoc IPA includes an Apple provisioning profile identifying enrolled test devices. Cloudflare processes requests and may maintain ordinary infrastructure logs.

## Sensor-only training (Beta 15)

No camera permission, ARKit camera tracking, photographs, video recording, or marker tracking is included in this release. Existing optical CSVs saved locally by earlier beta versions are left untouched by the update and are not newly collected or uploaded.

## Local manual-training measurements

SkateFit Manual Balance Coach records calibrated tilt, sideways wobble and candidate manual/nose-manual pose-hold durations from the board-mounted AirPod. Each completed session saves best holds, detailed per-attempt timing, mean angle, wobble, ending reason, settings, and initial heuristic stability scores locally. Raw readings remain in the original local motion CSV archive. These measurements are **not proof** of wheel contact or successful tricks. No raw GPS coordinates, video, or 3D translations are captured by the coaching system. Raw motion CSV continues under the existing local session archive.

## Retention

This development prototype currently has no automatic expiration or retention policy. Motion samples and labels remain stored until they are manually deleted as part of project maintenance. Local unsent batches are persisted on the iPhone to retry uploads after loss of connectivity.

## Sharing, sales and advertising

No data is sold to advertisers, and the app does not use advertising or tracking identifiers. The cloud development dashboard is intentionally open to the public, as explained above.

## Choices and contact

Cloud sync is off by default. The switch in Motion Lab → Advanced explicitly enables public experimental uploads. Turning it off also stops retrying any pending uploads until you choose to enable it again. This does not automatically erase already-uploaded sessions. You can submit an issue at [the project's GitHub repository](https://github.com/banddude/skatefit-airpods-motion/issues) about deleting a session or making a privacy-related change.

This privacy notice applies only to the experimental **SkateFit Motion Lab** prototype, not the separate production SkateFit application.
