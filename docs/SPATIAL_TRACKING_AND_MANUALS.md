# SkateFit Spatial Tracking & Manual Balance: What We Can Measure

Updated 2026-10-13. This is the engineering contract behind Manual Balance Coach.

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
| Camera-relative optical marker X/Y/Z and rotation | Opt-in ARKit image tracking of a known 120 mm printed square | **Yes, experimental** | Requires visible marker, correct printing and stationary iPhone. Only marker movement in camera coordinates, not deck centre or actual height. |
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

### Board Space Camera Lab (experimental Beta 14 implementation)

- Printable reference: [the original 120 mm marker PDF](../SkateMotion/Resources/SkateFit_Board_Tracking_Marker_120mm.pdf). Print at 100% actual size. Verify the 50 mm ruler line. The detected square must be exactly 120 mm wide or metric estimates will be systematically scaled incorrectly.
- Secure marker rigidly at a visible portion of the board. Keep the iPhone on a stationary tripod. The implementation uses ARImageTrackingConfiguration and an ARReferenceImage with 0.12 metre physical width.
- While ARKit reports the image anchor is tracked, transform each frame's marker and camera poses into camera-local coordinates using inverse(camera transform) times marker transform. This yields the 3D translation of the *marker* in metres and a relative orientation quaternion. Do not propagate estimates when tracking is lost.
- An explicit flat-board zero creates a baseline; delta X, Y and Z in centimetres and angular movement are the difference between the current marker and that baseline. Camera movement makes the baseline invalid. Board tilting can raise the marker even if a wheel stays on the ground, so this is not jump height or verified wheel contact.
- A separately opt-in, local-only CSV records only tracked marker X/Y/Z and orientation change, camera frame timestamps, monotonic receipt times, and approximately receipt-time-matched AirPod pitch/roll/yaw. These sensors do not have proven hardware synchronized clocks. No camera imagery, video, microphone recording or GPS coordinates are captured in the CSV.
- **Not physically validated:** frame rates, image target acquisition at long distances, poor lighting, deck spin, blurred motion, occlusion by the skater, ARKit drift, camera movement, or actual positioning accuracy must be tested against a tape measure. Do not claim reliable real-world 3D accuracy until then.

Future alternatives include markerless 2D object tracking from Apple's Vision framework, optical 6DoF pose estimation with measured camera intrinsics, and contact sensors for wheels or foot placement. Markerless 2D pixel displacement is not metric XYZ without additional geometry.

### Other optional hardware
A custom skateboard-mounted UWB or Bluetooth Channel Sounding ranging accessory could be integrated with Apple's Nearby Interaction accessory workflow. The AirPod itself is **not** exposed to developers as an arbitrary ranging tag through that API. Ranging alone may provide distance and sometimes direction to an anchor; robust board XYZ requires geometry, suitable anchors, hardware and testing.

A board-mounted wheel rotation or pressure sensor could independently verify rolling or wheel contact; this would make manual scoring much more reliable than pure IMU. Apple's ARKit tracks the iPhone's pose, not automatically a separate skateboard.

## References

- Apple Core Motion: https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager
- Apple device-motion gravity, acceleration, attitude: https://developer.apple.com/documentation/coremotion/cmdevicemotion
- Apple Core Location: https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization()
- Apple AR World Tracking: https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration
- Apple Vision object tracking: https://developer.apple.com/documentation/vision/vntrackobjectrequest
- Apple Nearby Interaction accessory ranging: https://developer.apple.com/documentation/nearbyinteraction/ninearbyaccessoryconfiguration

## Physical hardware release gate

Test real supported AirPods Pro off-ear on the deck after calibration. Record ground-truth video for nose-up and tail-up manual holds; make sure the mounted side is detected, the quaternion model renders real nose direction correctly, upside-down flip direction and side axes match observed motion, and the pose-hold score is believable. Then validate 15 Hz balance readout, 30 Hz board pose updates, pressure/temperature/battery cost, sample rate, connection recovery, motion discontinuities and GPS false fixes outdoors. Until then this is a **sensor-based coaching beta**, not validated precision hardware instrumentation.
