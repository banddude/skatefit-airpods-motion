# SkateFit Spatial Tracking & Manual Balance: What We Can Measure

Updated 2026-10-14. This is the engineering contract behind Manual Balance Coach.

## Measurement tiers

| Data | Source | In this build? | Accuracy / restrictions |
|---|---|---|---|
| Pitch (nose up/tail up), sideways tilt, face-down inversion | Board-mounted AirPod gravity + three-pose calibration | Yes | Relative to the flat reference. Rigid mount and real sensor stream required. |
| Full 3D board orientation, including complete 180° inversion and 360° rotation | Fused AirPod attitude quaternion re-expressed in skateboard coordinates | Yes | Relative orientation, not world compass heading. Heading may drift. When attitude is absent, only gravity tilt is available and flip axis is ambiguous at full inversion. |
| Gyro pitch/roll/yaw rates, angular travel | Three-axis angular velocity | Yes | Rate/relative travel, not verified completed trick or landing. |
| User acceleration, movement spikes | Three-axis gravity-corrected AirPod acceleration | Yes | Can detect movement and impacts, not prove flight, contact, or board position. |
| Manual/nose-manual pose-hold time | Pitch target, sideways tilt, angular rate, device sample timing | Yes | **Candidate hold of a board pose only.** Neither wheels nor feet are sensed. Timing stops on disconnection/inversion/excessive tilt. |
| Pitch wobble and stability | Running RMS of calibrated pitch about its measured mean, plus target error, roll, angular rates and acceleration | Yes | Technique feedback, **not a validated physiological training score**. Compare your own sessions. |
| Outdoor riding speed | Optional iPhone GPS/Core Location | Yes | iPhone velocity, not independent board velocity. Requires permission and adequate fix; no route or coordinates stored or uploaded. |
| AirPod-only translation X/Y/Z and vertical jump height | None | **No** | A single AirPod IMU's acceleration cannot be integrated into stable position because initial velocity, sensor bias and gravity subtraction error drift rapidly. Do not display fabricated XYZ or height. |
| Actual wheels and board contact with ground | Camera / wheel sensors / additional equipment | **No** | Required to distinguish a grounded manual from holding a board up, a lift, an ollie, or upside-down flight. |
| Actual rider's center of mass / foot position | Camera / wearable / pressure deck | **No** | Beyond a mounted AirPod's capability. |

## Orientation mathematics

- Calibration captures the 3 poses flat, tail down and nose down with one AirPod rigidly mounted. Three-axis gyroscope/acceleration and gravity variance checks require 1.5 seconds of continuous stationary data for each pose; moving or inconsistent/sideways reference poses are rejected. Those gravity vectors define a skateboard-local orthonormal basis (nose axis, deck normal, width axis).
- On each board-mounted AirPod device-motion reading, rotate those axes using the fused attitude quaternion. Compare the **current** basis against the **reference** basis; create a relative orientation matrix and convert it to a quaternion used directly by SceneKit.
- Crucially, do not reconstruct the final model from independent pitch and roll Euler angles. That approach becomes ambiguous during flips and can double-count the same inversion. Use the calibrated quaternion for full orientation.
- Gravity alignment between the current measured gravity and calibrated flat gravity determines whether the deck is wheels-down, on its edge, or inverted. Without fused attitude, it can still detect inversion, but cannot determine which way the deck flipped around its length or width when precisely upside down.
- Reject nonfinite or invalid quaternion measurements. Screen rendering and balance scoring fall back safely rather than displaying impossible coordinates.
- Relative yaw can drift. An AirPod has no documented API providing the board's absolute GPS position or a 6DOF translation vector.

## Coaching mathematics

- A qualified **pose hold** must stay within the user-selectable target angle range, below the calibrated nose/tail-ground contact limit, with limited lateral tilt and angular motion.
- Time is accumulated from **consecutive** fresh board-mounted sensor readings. It is never filled in across sensor dropout, stationary phone motion, air-worn earbuds or inverted board poses.
- A short transient is not recorded as an attempt. Time after ~350 milliseconds and personally selected one-to-sixty-second goals are recorded locally.
- Stability combines target angle error, lateral tilt, three orthogonal angular velocity projections, and user acceleration; all weights are initial heuristics that need physical testing. Wobble is the RMS deviation from the mean absolute pitch during a single hold. These are separate metrics and must not be conflated.
- Session records and personal bests are saved on-device. Existing raw 20-column CSVs remain unchanged for backward compatibility.
- This can support **practice progress**, but it cannot claim someone successfully landed a manual, or classify fakie/nose/wheel contact with certainty.

## Next step for true skateboard X/Y/Z and wheel-contact proof

### AirPod sensor-only approach

No camera or marker tracking is included. Gyroscope, calibrated quaternion attitude and gravity estimate relative 3D rotation and whether the deck is upside-down. The accelerometer measures user acceleration but cannot provide reliable absolute X/Y/Z through double integration, because unknown initial velocity, bias and gravity-removal errors accumulate. Optional foreground iPhone GPS only reports the iPhone's outdoor speed and stated accuracy, not deck position or manual validity.

### Other optional hardware
A custom skateboard-mounted UWB or Bluetooth Channel Sounding ranging accessory could be integrated with Apple's Nearby Interaction accessory workflow. The AirPod itself is **not** exposed to developers as an arbitrary ranging tag through that API. Ranging alone may provide distance and sometimes direction to an anchor; robust board XYZ requires geometry, suitable anchors, hardware and testing.

Wheel-rotation or contact sensors could independently verify rolling or wheel contact in a future hardware project; current AirPod-only training does not include them. No camera-based 3D board positioning is implemented or required.

## References

- Apple Core Motion: https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager
- Apple device-motion gravity, acceleration, attitude: https://developer.apple.com/documentation/coremotion/cmdevicemotion
- Apple Core Location: https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization()
- Apple Nearby Interaction accessory ranging: https://developer.apple.com/documentation/nearbyinteraction/ninearbyaccessoryconfiguration

## Beta 15 sensor quality

- Reject nonfinite acceleration, gravity, gyro or timestamps, implausible magnitude, duplicate and out-of-order AirPod frames.
- Use device timestamps when monotonically available for continuous hold duration while also enforcing host callback freshness; Bluetooth gaps cannot inflate attempts.
- Terminate each candidate hold when the board returns flat, moves too rapidly, tilts sideways, becomes inverted, or loses its sensor. Each completed hold is saved locally with duration, angle, wobble and end reason.
- Manual goals follow locally recorded bests using a small 1-to-60 second progression ladder; coaching metrics are heuristics and still require physical validation.
- No camera permission or optical marker assets are shipped in Beta 15. Earlier on-device files are left untouched.

## Physical hardware release gate

Test real supported AirPods Pro off-ear on the deck after calibration. Record ground-truth video for nose-up and tail-up manual holds; make sure the mounted side is detected, the quaternion model renders real nose direction correctly, upside-down flip direction and side axes match observed motion, and the pose-hold score is believable. Then validate 15 Hz balance readout, 30 Hz board pose updates, pressure/temperature/battery cost, sample rate, connection recovery, motion discontinuities and GPS false fixes outdoors. Until then this is a **sensor-based coaching beta**, not validated precision hardware instrumentation.
