# SkateFit Manual Runner: asset and license register

This register applies to the game added in October 2026 on the \`feat/manual-runner-v2\` branch.

| Asset | Source | Rights / conditions | Included |
|---|---|---|---|
| Night-city skyline, stars, moon, ground, obstacles, particles | Original SwiftUI Canvas drawing in \`RunnerSceneView.swift\` | Original project artwork, distributed under repository's MIT license | Yes |
| Rider silhouette, vector skateboard, trucks/wheels | Original programmatic Canvas drawing in \`RunnerSceneView.swift\` | Original project artwork under MIT | Yes |
| Calibrated motion visualization | Original SceneKit geometry in \`Board3DView.swift\` | Original project artwork under MIT; not a third-party skateboard model | Yes |
| Buttons, controls, iconography | Apple's SF Symbols exposed by SwiftUI | Apple platform assets, subject to Apple's SF Symbols license | iOS only |
| Haptics and simple feedback | UIKit \`UIFeedbackGenerator\` + built-in iOS system alert sounds | Apple system functionality, no third-party audio distributed | iOS only |
| App icon \`skatefit_icon.png\` | Existing repository asset, provenance not independently confirmed | **Commercial rights must be confirmed before launch** | Yes |

The game does **not** currently bundle a third-party 3D skateboard model, a licensed sound pack, commercial music, custom character sprites, third-party fonts, or purchased textures. In particular, the existing SceneKit skateboard is procedural geometry rather than an externally sourced, physically realistic board. Do not describe those assets as installed until they are actually committed and rights-verified.

Before App Store release:
1. Confirm chain-of-title for the icon, brand name and any new visual assets.
2. Record author, source URL, license version, download date and attribution for every new art, model, texture, animation, or music file.
3. Do not import assets whose commercial redistribution or bundling permission cannot be verified.
4. Validate Apple's latest SF Symbols and developer terms for platform-only symbols.

This is an inventory, not a substitute for legal review.


## Beta 15 sensor-only assets

The camera marker, printer PDF and camera modules were removed. The 3D board is original SceneKit geometry, not an external licensed model.


## Native tvOS candidate branding

The layered tvOS home-screen icon, App Store icon and Top Shelf image are resized/composited versions of the existing repository SkateFit icon. No new external artwork or font files are bundled. The existing icon's commercial provenance still requires the same pre-release rights check stated above. The TV game and board use the shared original Canvas and SceneKit geometry.
