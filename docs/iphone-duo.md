# iPhone Duo archive

Tr3k's App Store record is `6824752752`, bundle id `app.tr3k.ios`, team `DQA38RTNF7`. Version 1.0 build 20022 can stay in review. This Duo build is marketing version **1.0.1** and the build number is at least **20023**.

Building with the iOS 27.1 SDK is what lets the system draw the app full-bleed and move system bars vertical. The deployment target stays iOS 15.0 so current phones still launch. Do not set `IPHONEOS_DEPLOYMENT_TARGET` to 27.1.

## What this tree already does

- The window is created with `UIWindow(windowScene:)`. There is no `UIScreen.main` frame.
- `Tr3kBridgeViewController` republishes bounds, regular horizontal size class, safe area, and display scale on every layout. Fold and unfold resize the WKWebView because that web view is the controller's view.
- `preferredContentMode` is `recommended`, so the remote page at `https://tr3k.app/play/` uses the real view width.
- Regular width: Rolodex and the Start dock sit side by side on the home screen. During a Tr3k the map fills the leading side and the turn card sits in the trailing pane. Compact width keeps the single stack.
- Safe areas pad the header, dock, and rails. When the binary is built with Xcode 27.1, `verticalBarEdge` is published as `data-tr3k-vbar`.
- `UIHingeInteraction` is compiled only when the archive is built with Xcode 27.1 (`TR3K_DUO_SDK`). Every hinge and vertical-bar declaration is also marked `@available(iOS 27.1, *)` and called from `#available(iOS 27.1, *)`, so the iOS 15.0 deployment target still builds. A partially open hinge parks the pet and sends one existing coach line (`tr3kcoach` / `park`). Devices without a hinge leave that path idle. Older Xcode skips the hook instead of failing the compile.

## Toolchain check

`scripts/select-xcode.sh` selects the newest Xcode 27.1 or newer under `/Applications` and exports `TR3K_XCODE_DUO=1`. If that Xcode is missing it prints the blocker and leaves `TR3K_XCODE_DUO=0`.

The unsigned iOS check keeps compiling on the runner's default Xcode so pull requests still build. The TestFlight workflow stops before upload when `TR3K_XCODE_DUO` is not `1`, so a non-Duo binary is not uploaded in place of this submission.

This checkout's agent environment has no Xcode, so it cannot archive or upload. Run the upload from a Mac that has Xcode 27.1 or from a GitHub macOS runner that has it.

## Archive on a Mac

1. Install Xcode 27.1 or newer and open it once so the iOS 27.1 platform is downloaded.
2. From the repo root:

```bash
bash scripts/select-xcode.sh
xcodebuild -version
npm ci
npm test
npm run build
npx cap sync ios
node scripts/patch-ios.mjs
```

`xcodebuild -version` must report Xcode 27.1 or newer. `select-xcode.sh` prints the exact missing-toolchain message when it is not.

3. Upload with Fastlane (same secrets as `.github/workflows/testflight.yml`):

```bash
export ASC_KEY_ID=...
export ASC_ISSUER_ID=...
export ASC_KEY_PATH=...   # AuthKey_<id>.p8
export BUILD_NUMBER=20023 # any integer greater than 20022 and greater than every build already uploaded
bundle exec fastlane beta
```

Fastlane sets `MARKETING_VERSION=1.0.1`, `CURRENT_PROJECT_VERSION` from `BUILD_NUMBER`, and `SWIFT_ACTIVE_COMPILATION_CONDITIONS=TR3K_DUO_SDK` when Xcode is 27.1 or newer. The lane uploads to TestFlight and does not submit for review (`skip_submission`).

`TR3K_ALLOW_OLDER_XCODE=1` lets the lane archive on an older Xcode. That ipa is not a Duo build. Do not attach it to the Duo submission.

4. Or archive in Xcode 27.1: scheme App, Release, Any iOS Device. Marketing version 1.0.1. Build number greater than 20022. Distribute to App Store Connect and stop on TestFlight. Do not submit for review in that dialog.

Confirm the binary's SDK in the archive log (`iPhoneOS27.1.sdk` or newer). A binary linked with an older SDK runs on Duo in the compatibility frame and will not earn the badge.

## App Store Connect, after TestFlight processing

Do not cancel the in-review 1.0 build 20022 as part of preparing this archive. Uploading 1.0.1 to TestFlight does not attach it to that review and does not cancel it.

Apple will not start a second review while 1.0 is Waiting for Review. Two ways to ship Duo, both done by a person in App Store Connect:

- Leave 1.0 (20022) in review. After it is accepted or rejected, create version 1.0.1, select the Duo build (20023 or higher), add the Duo screenshots below, and submit 1.0.1.
- If the Duo binary should replace 20022 before that review finishes, a person rejects 1.0 from review, then selects the Duo build and adds the Duo screenshots on the version that will be submitted. This repository's automation does not do that rejection.

Screenshots that turn on the Made for iPhone Duo badge:

| Display | Portrait | Landscape |
| --- | --- | --- |
| Outer | 1398×2034 | 2034×1398 |
| Inner | 2007×2853 | 2853×2007 |

Use the iPhone Duo simulator in Xcode 27.1. Capture the inner display with the Rolodex and Start dock side by side, and the outer display with the single stack. Add a navigation shot so the map pane is visible. Upload those in the iPhone Duo screenshot slots. The product page shows the badge after the version that contains them is submitted. Preview the set in App Store Connect before submitting.

Optional: a featuring nomination can say the app is optimized for iPhone Duo, including the partially open pose (pet park pose and one coach line).
