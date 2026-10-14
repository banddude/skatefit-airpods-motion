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
- Cloudflare bucket `skatefit-motion-betas` holds `ios/SkateFitMotionLab-0.1.0-1.ipa` and `ios/SkateFitMotionLab-icon.png`.
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

**When shipping a new build:** increment `CFBundleVersion` in `project.yml`, regenerate the Xcode project, and rebuild. Update both the object key and OTA metadata version in `backend/src/beta.js` before redeploying the Worker. Upload the newly exported IPA under the matching key:

```bash
wrangler r2 object put \
  skatefit-motion-betas/ios/SkateFitMotionLab-0.1.0-1.ipa \
  --file /tmp/skatefit-motion-beta-export/SkateMotion.ipa \
  --remote --content-type application/octet-stream

wrangler deploy
```

The command above illustrates the **existing build 1** path. For future builds, change the object path to match the incremented version/build.

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
