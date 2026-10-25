# Tr3k

Treasure-hunt treks for any EV that can use the NACS charging network. One QR scan opens the iPhone beta or the web app. Rewards are in-app collectibles with no cash value.

Tr3k is independent. It is not affiliated with, endorsed by, or sponsored by any vehicle maker, charging network, or shopping center.

## Play the launch trek

Saturday, October 24, 2026. Buford, Georgia. Two sidewalk stops, 250 m pickup.

1. Open the map.
2. Check in inside the ring, or tap **Demo mode — check in from anywhere**.
3. In driving mode, or if the phone is moving, **Park safely first**.
4. The camera opens with a fortune cookie in front of you. Tap it. The shell splits, a light bursts, and the rarity reward rises and spins.
5. Keep it. It lands in the Pack.

If the camera is denied, the same crack plays on a plain stage.

Coordinates live only in `src/trek.js`.

| Stop | Pin | Where |
| --- | --- | --- |
| 1 | 34.0811107, -83.9872860 | Public sidewalk, west side of Buford Dr, in front of 3500 Buford Dr |
| 2 | 34.0710375, -83.9842244 | Public sidewalk where Mall of Georgia (3333 Buford Dr) meets Buford Dr |

Stop 1 is the Census address-range point for 3500 Buford Dr, moved 14 m onto OpenStreetMap sidewalk way 1121251047. Stop 2 is the sidewalk (way 397665397) at the mall parcel's Buford Drive frontage, not the building interior. The public store list puts that company's Buford pop-up at the mall's street address and does not list a separate service building at 3500. The pin stays on the public sidewalk either way.

## Web

```bash
npm install
npm run dev
```

`npm run build` writes the Cloudflare Pages output to `dist`. Point tr3k.app at that directory (`npm run build`, output `dist`). `https://tr3k.app/get` is `dist/get/index.html`.

`public/get/testflight.js` holds `TESTFLIGHT_URL`. iPhones go there once `REPLACE_ME` is a real join code. Everyone else goes to the web app. Until the code is set, an iPhone stays on the get page and can still play in the browser.

```bash
npm run qr
```

writes `print/tr3k-get-qr.png`, a 4×6 inch card for `https://tr3k.app/get`.

## iPhone

Capacitor app **Tr3k**, bundle id `app.tr3k.ios`, team `DQA38RTNF7`, App Store Connect app `6824752752`.

On iPhone the crack-open is ARKit: a world-tracked cookie about 0.65 m in front of the camera, tap to split the shell, then the reward rises and spins. WebXR is not available in iOS Safari or WKWebView. AR Quick Look can show a USDZ, but it cannot tell the app that the cookie was tapped, so the pack would not update. A camera-and-three.js overlay is the web fallback and the path used at tr3k.app. ARKit is the one that reliably places the cookie in the room on a stranger's iPhone. The plugin is local (`plugins/tr3k-ar`) and links only Apple frameworks, so the TestFlight job does not need a model pipeline.

### Native map

The iOS shell can show a real MapKit map (`MKMapView`) on top of the WebView during navigation: standard, satellite, hybrid, and muted styles, pinch zoom, compass, follow, and a pitched camera with 3D buildings where Apple provides them. It does not use a MapKit JS token.

`window.tr3kNative` (shim version 6) is injected at document start and fires `tr3knativeready`. On Start Tr3k, call `showMap`, `requestPermissions({ always: true })`, and `setStops` so arrival alerts can fire in the background. Spoken directions use `speak` and `stopSpeaking` (`AVSpeechSynthesizer`), so a prompt keeps playing with the screen locked. On end navigation, call `hideMap`, `stopSpeaking`, and `endLiveActivity`. While a Tr3k is active the lock screen and Dynamic Island show the stop, distance or ETA, progress, and the next action (`Drive`, `Park`, `Hunt AR`, `JOIN Live Drop`), using those same navigation calls. Pass `insets` for the page's top and bottom chrome. Share with `share`, and read `tr3kdeepLink` for `https://tr3k.app/play/?trek=<id>`. Cache the nearby list with `saveOfflineTreks` (aliases `saveOffline` and `offlineSave`); that same slim record fills the home screen widget, which also reloads about hourly from `https://tr3k.app/api/nearby`. Sign in with Apple is optional via `signInWithApple`, `getAppleSession`, and `signOutApple`. A stop can carry an X Live Drop: `setLiveDrop`, then `onLiveDropUnlock`, or the shell shows the JOIN sheet itself. `openXLiveDrop` opens the X app. The method list for the web team is `plugins/tr3k-native/README.md`. In a normal browser, `tr3kNative` is absent and the site keeps its current map.

```bash
npm run build
npx cap sync ios
node scripts/patch-ios.mjs
```

Joseph builds on the macOS GitHub Actions runner. Workflow: `.github/workflows/testflight.yml`.

### Secrets that must be set

App Store Connect API key (Admin on team `DQA38RTNF7`):

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_KEY_P8` — raw PEM, including the BEGIN and END lines

The TestFlight job uses that key with `cert` and `sigh` to create an Apple Distribution certificate and an App Store profile for `app.tr3k.ios` in a temporary keychain, then archives and uploads. No p12 and no match repo are required. Each fresh runner that does not already have the certificate's private key creates a distribution certificate. Apple caps how many of those a team can hold.

Optional, for the Pages deploy step:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

No secret values live in this repo. The TestFlight job stops with the missing names if the API key is unset. The bundle id on the App Store Connect app must be `app.tr3k.ios`. The home-screen name in the binary is Tr3k.
