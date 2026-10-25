# Tr3k native bridge

iOS-only Capacitor plugin (`jsName` `Tr3kNative`). The shell injects `window.tr3kNative` at document start on every page, including `https://tr3k.app/play/`. Shim version is `window.tr3kNative.version` (currently **6**).

Version 2 is the MapKit map (`MKMapCamera` pitch and Apple's 3D buildings). The browser keeps its own map. This plugin does not load MapKit JS and does not need a MapKit token.

Version 3 adds three product paths on the same object: background Tr3k stop arrival alerts, the share sheet plus deep links, and haptics plus a local Live Activity. Map, location watch, and `openAR` stay as they were.

Version 4 adds the on-device offline cache (the same record feeds the home screen widget), AR camera status plus Settings, and an optional Sign in with Apple session. Every call returns a Promise. The shim still fires `tr3knativeready` at document start.

Version 5 adds the X Live Drop. A stop can carry a Space or a group Chat. Arrival plays a strong haptic and emits `liveDropUnlock`. The page draws the moment, or the shell does when the page has not subscribed. `openXLiveDrop` hands off to the X app. There is no X token and no chat server.

Version 6 adds spoken directions. `speak` and `stopSpeaking` use `AVSpeechSynthesizer`, so a prompt that has started keeps playing with the screen locked. The page at `https://tr3k.app/play/` already calls these when they exist.

## Background location and arrival alerts

Call this when a Tr3k starts, after When In Use is enough for the map:

```js
const auth = await tr3kNative.requestPermissions({ always: true });
// auth.location is "always" | "whenInUse" | "denied" | "restricted" | "prompt"
// auth.alwaysPrompted is true when the Always upgrade dialog was shown
// auth.backgroundAlerts is true only for "always"

await tr3kNative.requestNotifications();
await tr3kNative.setStops(
  [{ id: "1", name: "Stop 1", lat: 34.0811107, lng: -83.987286 }],
  {
    radius: 75,
    title: "You've arrived at a Tr3k stop",
    body: "Open Tr3k to check in."
  }
);
tr3kNative.onArrival((event) => {
  // event.stopId is the stop id you passed to setStops
  tr3kNative.haptic("success");
});
```

`requestPermissions({ always: true })` asks for When In Use first, then for Always. If Always is denied, `getLocation`, `watchLocation`, and the map keep working with When In Use. Region alerts do not: iOS only delivers stop regions with Always.

`setStops` stores the stops and asks for Always once per launch if the app only has When In Use. It returns `{ monitored, pending, supported, location, backgroundAlerts }`. `monitored` is how many regions are armed right now. `pending` is how many were saved and will arm after Always is granted. Up to 20 stops. Radius is clamped to at least 30 meters.

The defaults stay "You've arrived at a Tr3k stop" and "Open Tr3k to check in." Pass `title` and `body` to replace them. A stop `name` becomes the notification subtitle.

The local notification is scheduled on the phone. There is no server push. The same alert fires when Tr3k is in the background or has been suspended. If iOS relaunches the app for the arrival, the saved stops are restored and the notification is posted before the web view loads. `onArrival` still receives `{ stopId }` once the page is listening (`retainUntilConsumed`).

`clearStops()` removes the regions and the saved set.

Info.plist purpose strings:

- When In Use: nearby hunts, turn-by-turn directions, and reaching each Tr3k stop.
- Always: Tr3k stop arrival alerts while the app is in the background or not open. Tr3k only watches the stops on the current hunt.

`UIBackgroundModes` includes `location` so those region events can wake the app, and `audio` so spoken directions can continue with the screen locked. Outside an active navigation the shell does not keep the GPS radio on in the background; follow and `watchLocation` pause until Tr3k is open again. During navigation (the native map is on screen) location keeps updating with the screen locked, so the page can speak the next line. iOS shows the background location indicator while that is happening. There is no new permission prompt. The When In Use purpose string already covers turn-by-turn directions.

## Spoken directions

Web speech stops when the phone sleeps. The shell speaks with `AVSpeechSynthesizer` instead.

```js
await tr3kNative.speak({ text: "In 500 feet, turn left.", interrupt: true });
// { spoken: true, id, queued: true, guidance: true }
// { spoken: false, reason: "muted" | "empty" | "session" }

await tr3kNative.stopSpeaking();
// { stopped: true, speaking }
```

`speak("Turn left")` is the same as `speak({ text: "Turn left", interrupt: true })`.

`https://tr3k.app/play/` already does this. `say()` calls `speak({ text, interrupt: true })` and does not use `speechSynthesis` when `tr3kNative.speak` is a function. Mute lives in the page (`localStorage` key `tr3k_voice_mute`). The mute button and end navigation call `stopSpeaking()`. Pass `mute: true` or `muted: true` on `speak` and the shell stays quiet and clears anything already talking.

`rate` is the Web Speech rate. `1` is normal. The page omits it, and the shell uses `1.05`. Pass `rateUnit: "av"` to set `AVSpeechUtterance.rate` directly (0 to 1). `lang` defaults to `en-US`. The shell prefers a premium or enhanced voice for that language. `stopSpeaking({ boundary: "word" })` finishes the current word. The default cut is immediate.

The audio session category is `.playback` with mode `.spokenAudio` and options `.duckOthers` and `.interruptSpokenAudioAndMixWithOthers`. Playback is what iOS requires for audio to continue in the background. Spoken-audio mode is the continuous-speech mode. Ducking keeps music playing underneath at a lower volume instead of stopping it. The session is armed when navigation starts (unless voice is muted) and released on mute, `stopSpeaking`, or `hideMap`, which is when other audio returns to full volume.

Info.plist `UIBackgroundModes` must contain `audio` in addition to `location`. `scripts/patch-ios.mjs` puts both back after `npx cap sync ios`. No entitlement is required for the audio background mode.

`speechStart` and `speechFinish` are optional listeners (`speechFinish.reason` is `finished` or `cancelled`). The play page does not wait on them.

With the screen locked, a sentence that has started finishes. Later lines play when a location update reaches the page. iOS can still suspend the web view between prompts if it decides the app is idle. Tr3k keeps the playback session active and keeps GPS on for the open navigation so those updates can arrive. This is as far as a web navigation loop can go under iOS background rules. Tr3k does not play a silent loop to stay awake.

## Share sheet and deep links

```js
await tr3kNative.share({
  title: "Tr3k",
  text: "Walk this Tr3k with me",
  url: "https://tr3k.app/play/?trek=" + encodeURIComponent(trekId)
});
// { completed: true } if the user finished an activity, otherwise { completed: false }
```

`share` presents `UIActivityViewController`. `title` is the mail subject. `text` and `url` both go on the sheet when you pass them.

Canonical URLs, stable for the web team:

| Open this | Result |
| --- | --- |
| `https://tr3k.app/play/?trek=<id>` | Tr3k id in `trekId` |
| `https://tr3k.app/play/?quest=<id>` | Quest id in `questId` |
| `https://tr3k.app/t/<id>` | Short Tr3k link, same `trekId` |
| `https://tr3k.app/q/<id>` | Short quest link, same `questId` |
| `tr3k://play/?trek=<id>` | Custom scheme, same fields |
| `tr3k://t/<id>` and `tr3k://q/<id>` | Custom scheme, same fields |

`trekId` is also accepted as a query name, and `questId` too. The canonical query names are `trek` and `quest`.

The shell does not change the WebView URL. On a cold start and on a later open it emits:

```js
window.addEventListener("tr3kdeepLink", (event) => {
  const { url, path, query, trekId, questId, issuedAt } = event.detail;
});

const remove = tr3kNative.onDeepLink((link) => {
  // same object as event.detail; replays the last link if you subscribe late
});
```

`path` is normalized, so `tr3k://t/buford` and `https://tr3k.app/t/buford` both report `path: "/t/buford"`. `query` is a string map. `issuedAt` is a number that stays the same for one delivery, including the startup replay. `getLastDeepLink()` resolves with that object, or `{}` when the app was not opened from a link.

`https://tr3k.app` and `https://www.tr3k.app` are accepted. Other hosts are ignored. `tr3k://localhost` is the shell's own origin and is not a deep link.

The app entitlement is `applinks:tr3k.app` (associated domains). Team `DQA38RTNF7`, bundle id `app.tr3k.ios`, so the Apple app id is `DQA38RTNF7.app.tr3k.ios`. The site file is not in this repo. See the pull request for the `apple-app-site-association` body Joseph still has to host.

## Haptics

```js
await tr3kNative.haptic("light");    // turn prompt
await tr3kNative.haptic("medium");
await tr3kNative.haptic("success");  // arrival
await tr3kNative.haptic("warning");
```

Also accepted: `heavy`, `soft`, `rigid`, `error`, `selection`, and `strong` (heavy impact plus a success notification, used when a live drop unlocks). An unknown kind resolves `{ played: false, kind }` and does not throw. `haptic({ kind: "success" })` works too. These are impact and notification generators on the phone. The web nav loop should call them; the native arrival notification does not vibrate by itself. The live drop unlock does.

## X Live Drop

Geo-gated handoff into an X Space or X group Chat. The page registers the drop. The existing stop geofence is the unlock. Payloads stay slim: `stopId`, `type` (`"space"` or `"chat"`), `url` (or `deepLink`), optional `title`, optional `unlockRadiusM`. No tokens, no message bodies, no custom chat.

```js
await tr3kNative.setLiveDrop({
  stopId: "buford-dr-3500",
  type: "space", // or "chat"
  url: "https://x.com/i/spaces/YOUR_SPACE_ID",
  title: "Live",
  unlockRadiusM: 75
});
// { saved: true, stopId, type }
// { saved: false, reason: "invalid" } when the id or the X url is rejected

const drop = await tr3kNative.getLiveDrop("buford-dr-3500");
// { found: true, stopId, type, url, title?, unlockRadiusM?, demo }
// { found: false } when that stop has no drop

await tr3kNative.setLiveDrops([ /* same objects */ ]); // replace: true
await tr3kNative.clearLiveDrops();                      // or clearLiveDrops(stopId)
```

`setStops` still arms the regions. Pass the same `unlockRadiusM` as `radius` so the geofence matches the drop. A stop may also include `liveDrop: { type, url, title?, unlockRadiusM? }` and `setStops` will save it. `clearStops` does not remove drops; call `clearLiveDrops`.

Empty `url` is not stored. For an Internal demo with no Space id, send the public handoff `https://x.com/i/spaces` (or `https://x.com/messages` for chat) and `demo: true`. The launch page does that when its config url is empty. Do not put a token in the url.

When a monitored stop with a drop is entered, the shell plays `haptic("strong")` and emits `liveDropUnlock` (`retainUntilConsumed`). The same stop will not emit again for 30 seconds.

```js
tr3kNative.onLiveDropUnlock((event) => {
  // event: { stopId, type, url, title?, unlockRadiusM?, demo, source, unlockId, issuedAt }
  // source is "arrival" or "preview". issuedAt is milliseconds.
  // Draw one black screen, one button, one line: "Only people at this stop."
  const opened = await tr3kNative.openXLiveDrop(event.url);
  // { opened: true, url, via } via is "x", "twitter", or "https"
  // { opened: false, reason: "invalid" | "unavailable" }
});
```

`onLiveDropUnlock` tells the shell the page owns the surface, so the native sheet stays down. Events older than three minutes are ignored. If the page never subscribes, the shell shows that same sheet: black, system type, huge headline, one button (`JOIN 𝕏 SPACE` or `JOIN 𝕏 CHAT`), and the line "Only people at this stop." Swipe down dismisses. The sheet is also what you get if the web view is not ready when the geofence fires, including a relaunch from a background arrival. The drop is restored from device defaults (`tr3k.livedrop.v1`).

`openXLiveDrop` tries `x://`, then `twitter://`, then `https://x.com/...`. A Space id becomes `x://spaces/<id>`, `twitter://spaces/<id>`, and `https://x.com/i/spaces/<id>`. Chat uses `x://messages` and `twitter://messages`, then the https link you passed. Hosts other than `x.com` and `twitter.com` are rejected. Info.plist `LSApplicationQueriesSchemes` includes `twitter` and `x` so the shell can see whether the app is installed.

```js
await tr3kNative.previewLiveDrop();                         // saved drop, or the demo
await tr3kNative.previewLiveDrop({ stopId: "buford-dr-3500" });
```

`previewLiveDrop` is the same haptic and event without walking to the pin. Internal testers can also open `tr3k://live-drop`, `https://tr3k.app/play/?liveDrop=1`, or `?liveDrop=` plus an `https://x.com/...` url. `?liveDropType=chat` selects chat. Nothing in that link is a secret.

Arm the regions with Always location, then walk into the stop, or run the preview. The button leaves Tr3k and opens X.

## Live Activity

Local ActivityKit activity for the Tr3k that is already on screen. No push token and no push-to-start. The same `startLiveActivity` / `updateLiveActivity` / `endLiveActivity` calls are the channel. The shell also mirrors the navigation calls the page already makes (`showMap`, `setStops`, `setRoute`, `speak`, arrival, `openAR`, live drop, `hideMap`), so the lock screen keeps moving when the page does not send a separate update.

Lock Screen and the expanded Island show the trek or quest name (the stop name when there is one), distance or ETA to the next stop, stop progress (`2/4`), and one next-action line: `Drive`, `Park`, `Hunt AR`, or `JOIN Live Drop`. The field is black. Type is white and silver. Gold is only the live-drop and rare-hunt states. Compact Island shows progress and the distance, or `Park` / `Hunt` / `Drop`.

Tap the activity to open `https://tr3k.app/play/?trek=<id>` (or `?quest=<id>`). That is the same universal link as the home screen widget.

```js
const started = await tr3kNative.startLiveActivity({
  trekId: "buford",
  trekName: "Buford",
  stopName: "Lenox Square",
  stopIndex: 2,          // 1-based. stopCount is the total. "2/4" is also accepted as progressText
  stopCount: 4,
  distanceText: "400 m",
  etaText: "5 min",
  action: "Drive"        // Drive | Park | Hunt AR | JOIN Live Drop
});
// started.started is false with reason "unsupported" below iOS 16.2
// or "disabled" when Live Activities are off in Settings

await tr3kNative.updateLiveActivity({
  instruction: "Turn left",
  distanceText: "80 m",
  etaText: "1 min"
});
// phase: "park" | "hunt" | "drop" | "complete" also sets the action.
// rare: true, or rarity "rare" | "epic" | "legendary", turns a Hunt AR line gold.
// kind: "quest" with questId / questName opens ?quest= on tap.

await tr3kNative.endLiveActivity();                  // removes it now, unless every stop has been arrived
await tr3kNative.endLiveActivity({ dismissal: "immediate" });
await tr3kNative.endLiveActivity({ dismissal: "default" }); // about 45 seconds, then gone
```

`distance` and `eta` are accepted aliases of `distanceText` and `etaText`. Omitted fields keep the previous text. `trekName` defaults to "Tr3k". `stopIndex` is 1-based.

Lifecycle without a separate call: the activity starts once the native map is up and stops or a route are set (or when `startLiveActivity` runs). Spoken lines such as "In 500 feet, turn left" and "Park safely first" update the card. Arrival switches it to `Park`, or `JOIN Live Drop` when that stop has a drop. `openAR` switches it to `Hunt AR`. `hideMap` ends it (immediately on cancel, or a short `Complete` card when every stop was arrived). `endLiveActivity` does the same. A finished card leaves the lock screen after about 45 seconds. A cancel removes it now. Starting a trek replaces any activity already on screen.

The widget extension bundle id is `app.tr3k.ios.LiveActivity`. It links the `Tr3kActivityKit` module, which is also what the shell uses, so the activity type matches. The app Info.plist key `NSSupportsLiveActivities` is true. There is no Push Notifications capability. iOS 15 still installs; `startLiveActivity` resolves `unsupported` there.

Joseph: the TestFlight lane registers `app.tr3k.ios.LiveActivity` and requests an App Store profile for it. If that step fails, create that bundle id on team `DQA38RTNF7`. Local Live Activities do not need a separate portal capability beyond the Info.plist flag. If a future Apple portal toggle appears for Live Activities on `app.tr3k.ios`, turn it on. Do not enable push for this. The Live Activity extension does not join the App Group.

## Offline cache (shim v4)

The play page calls these names, in order. The first of each is the native plugin method. The other two are shim aliases of that method. All return Promises.

| Action | Call, then aliases |
| --- | --- |
| Save | `saveOfflineTreks`, then `saveOffline`, then `offlineSave` |
| Get | `getOfflineTreks`, then `getOffline`, then `offlineGet` |
| Clear | `clearOfflineTreks`, then `clearOffline`, then `offlineClear` |

```js
await tr3kNative.saveOfflineTreks({
  key: "tr3k.offline.v1",
  v: 1,
  at: Date.now(),
  lat: 34.0811107,
  lng: -83.987286,
  nearby: [
    { id: "buford", name: "Buford", lat: 34.0811107, lng: -83.987286, category: "walk", order: 1, copy: "Start here" }
  ],
  active: { id: "buford", name: "Buford", kind: "trek" }
});

const cached = await tr3kNative.getOfflineTreks({ key: "tr3k.offline.v1" });
// same object the save stored, or {} when nothing is cached

await tr3kNative.clearOfflineTreks({ key: "tr3k.offline.v1" });
// { cleared: true, key: "tr3k.offline.v1" }
```

`nearby` and `active` are slim Tr3k refs only. Kept keys: `id`, `trekId`, `questId`, `name`, `placeName`, `place`, `title`, `lat`, `lng`, `latitude`, `longitude`, `lon`, `category`, `order`, `routeOrder`, `copy`, `gameCopy`, `kind`, `type`. Phone numbers, URLs, map items, and raw place records are dropped. A string id is accepted and stored as `{ id }`.

The saved ref always has `id`, `kind` (`"trek"` or `"quest"`), and `name` when a place alias was present. `lat` / `lng` are set when the coordinate is valid. `order` is filled from `routeOrder`, and `copy` from `gameCopy`. Original allowlisted keys are kept too, so either alias still works on get. Nearby is capped at 24. `copy` / `gameCopy` are capped at 500 characters. Other strings are capped at 160, and `id` at 128.

The stored record is only `{ key, v, at, nearby, active, lat, lng }`. A missing `active` is stored as `null`. A save replaces the whole record for that key. Get returns that object (a JSON object, not a string). No cache returns `{}`, so a missing `nearby` means there is nothing stored. A saved empty list is `{ key, v, at, nearby: [], active: null }`.

The default key is `tr3k.offline.v1`. A key may use letters, digits, `.`, `_`, and `-`, up to 80 characters. Anything else uses the default key. The record lives in the App Group `group.app.tr3k.ios` (`UserDefaults` key `cache.<key>`, plus `tr3k-offline-v1.json` for the default key). There is no cloud copy.

Saving or clearing reloads the home screen widget. The widget reads the default key only.

## Home screen widget

Widget extension bundle id `app.tr3k.ios.widget`, kind `app.tr3k.ios.widget.home`. Small and medium, branded Tr3k (`#14110e` with the orange accent). It shows "Tr3ks near you", the last active Tr3k, or "Start Tr3k" when the cache is empty.

A tap opens `https://tr3k.app/play/?trek=<id>` when the ref is a Tr3k, or `?quest=<id>` when `kind` is `"quest"`. The small widget uses the active ref when one is saved, otherwise the single nearby ref, otherwise `https://tr3k.app/play/`. The medium widget gives each row its own link. There is no separate widget JS API: `saveOfflineTreks` on the default key is what refreshes it.

The widget and the app share the App Group. The Live Activity target does not.

Joseph, before the signed TestFlight upload can include this extension:

1. Create the App Group `group.app.tr3k.ios` (name Tr3k) on team `DQA38RTNF7`. The App Store Connect API key cannot create App Groups.
2. Assign that group to `app.tr3k.ios` and `app.tr3k.ios.widget`.
3. The lane registers `app.tr3k.ios.widget` and requests the profile `tr3k-widget-appstore`. If capability settings are rejected, the log names the portal toggle to confirm.

The unsigned pull-request build does not need those portal toggles.

## AR permission status

`openAR` still resolves the happy path `{ opened: true, reason: "opened", tier, prize }` and now also returns `supported`, `camera`, and `canOpenSettings`. Camera is checked before the modal is presented. Denied or restricted resolves (it does not reject) so the page can show its own message. There is no blank camera modal.

```js
const result = await tr3kNative.openAR({ tier: "rare", prize: "pumpkin" });
// result.reason: "opened" | "closed" | "camera_denied" | "camera_restricted" | "unsupported" | "not_ready"
// result.camera: "authorized" | "denied" | "restricted" | "notDetermined" | "unavailable"
// result.canOpenSettings is true for denied and restricted
// result.message is a sentence the page can show

if (result.canOpenSettings) await tr3kNative.openSettings();
```

`arStatus()` returns the same fields without prompting and without presenting AR (`reason` is `camera_prompt` while the system dialog has not been shown). `isARSupported()` is still a boolean hardware check.

`Tr3kAR.open` keeps `{ cracked, reason }` and adds `supported`, `camera`, `canOpenSettings`, and `message`. It still rejects only when the app view is not ready. `Tr3kAR.isAvailable` is still the hardware check (`available` follows `supported`) plus those extra fields. `Tr3kAR.openSettings()` opens Settings the same way.

The camera purpose string says Tr3k places an AR collectible, a fortune cookie or a glowing pumpkin, and that nothing is recorded or uploaded. The motion string says the collectible stays in place while you look around.

## Sign in with Apple

Optional. The app launches without it. The session is the Apple user id plus name and email only when Apple sends them on the first grant. It is stored on the device in the app's own defaults (not the App Group, so the widget cannot read it). Identity tokens and authorization codes are not stored.

```js
const session = await tr3kNative.signInWithApple();
// { signedIn: true, user, email?, fullName?, givenName?, familyName? }
// Cancel: the stored session is left as-is, plus reason "canceled".
// Failure: stored session left as-is, plus reason "failed" and
// message "Sign in with Apple did not finish."
// A second call while the sheet is up: reason "in_progress".
// No presenter: reason "unavailable".

const current = await tr3kNative.getAppleSession();
// local read, no second prompt. { signedIn: false } or the stored session.

await tr3kNative.signOutApple();
// { signedIn: false }
```

The same user id merges a later grant with the name and email already stored. A different user id replaces the session. `signedIn` in a cancel or failure payload reflects what is still stored.

The entitlement is `com.apple.developer.applesignin` = `Default` on `app.tr3k.ios` only.

Joseph: enable Sign in with Apple on the App ID `app.tr3k.ios` (App Store Connect app `6824752752`) if the upload is rejected. The lane tries `APPLE_ID_AUTH` with primary app consent. The unsigned pull-request build does not need that toggle. Do not enable push.

## When the page is inside the app

```js
const native = window.tr3kNative;
if (native && (await native.isNativeMapSupported())) {
  // use the methods below
}
```

`isNativeMapSupported()` resolves to `false` when the bridge is missing, so the same page can keep MapKit JS in Safari.

Listen for `tr3knativeready` if you call the bridge from a script that runs at document start. Calls made after the page's own scripts run can use `window.tr3kNative` directly.

## Show and hide

The map is a native `MKMapView` inserted **above** the WebView, pinned to the WebView's edges. It is not a transparent hole behind the page: a WebView on top would swallow pinch, rotate, and pitch gestures.

`hideMap()` removes that view. The WebView is fully visible and receives touches again. Call it when navigation ends (`endNav`). The last route, map type, and camera stay in memory and come back on the next `showMap()` unless you pass new options.

```js
await tr3kNative.showMap({
  mapType: "standard", // standard | satellite | hybrid | mutedStandard
  center: { lat: 34.0811107, lng: -83.987286 },
  zoom: 17,            // web-mercator style, about 2–21
  pitch: 60,           // degrees. 0 is top-down. About 55–70 shows buildings.
  heading: 0,          // degrees clockwise from north
  follow: true,
  followHeading: false,
  animated: false,
  insets: { top: 96, right: 0, bottom: 168, left: 0 }
});

await tr3kNative.hideMap();
```

`insets` are CSS pixels from the **webview** edges. On iOS those are points. The map does not cover that margin, so HTML in the top and bottom bands stays visible and tappable. Put the nav chrome there.

`holes` are viewport rectangles, also CSS pixels, from `getBoundingClientRect()` (the page does not scroll). Each hole is cut out of the map and touches pass through to the WebView. Use this for a floating button that must sit over the map. Call `setLayout` again when the rects move.

```js
const rect = button.getBoundingClientRect();
await tr3kNative.setLayout({
  holes: [{ x: rect.x, y: rect.y, width: rect.width, height: rect.height }]
});
```

Pass `holes: []` to close them. Omitted `insets` or `holes` on `setLayout` leave that part as it was.

The first `showMap` that has a center or a GPS fix and does not pass `pitch` uses **55 degrees** so the 3D camera is on. Pass `pitch: 0` for a top-down start. Zoom defaults to **16** in that same case. Later shows keep the current camera unless you pass new camera fields.

`showMap`, `setCamera`, `setMapType`, `zoomIn`, `zoomOut`, `resetNorth`, and `setFollow` resolve with a camera snapshot:

```js
{
  visible, mapType, latitude, longitude,
  center: { lat, lng },
  zoom, pitch, heading,
  follow, followHeading,
  latitudeDelta, longitudeDelta,
  insets: { top, right, bottom, left }
}
```

## Controls to wire

| Page control | Call |
| --- | --- |
| Standard / Satellite / Hybrid / Muted | `setMapType("standard" \| "satellite" \| "hybrid" \| "mutedStandard")` |
| Zoom + / − | `zoomIn()` / `zoomOut()` (one web-mercator level; follow stays on) |
| 3D tilt | `setCamera({ pitch: 65 })` and `setCamera({ pitch: 0 })` |
| Compass / north-up | `resetNorth()` |
| Follow me | `setFollow(true)` or `setFollow(false)` |
| Follow with device heading | `setFollow(true, { followHeading: true })` |

`setCamera({ center, zoom, span, distance, pitch, heading, animated })` moves the camera directly.

- `span` is `{ latitudeDelta, longitudeDelta }`.
- `distance` is meters from the ground to the camera. It wins over `zoom` and `span`.
- An explicit `center` turns follow off and emits `followPaused` with `reason: "camera"`.
- Pitch, heading, and zoom do not turn follow off.

`resetNorth()` sets heading to 0. If follow was rotating with the device, it stays centered but stops rotating.

`setFollow(false)` or a one-finger pan pauses follow. Pinch-zoom, rotation, and pitch do not.

```js
tr3kNative.onFollowPaused((camera) => { /* camera.reason is "pan" or "camera" */ });
tr3kNative.onCameraChanged((camera) => { /* throttled; sync a compass widget */ });
tr3kNative.onMapReady((camera) => {});
tr3kNative.addMapListener("cameraChanged", (camera) => {});
```

Subscribe to `onMapReady` before `showMap`, or just use the promise `showMap` returns. `onFollowPaused` and `onCameraChanged` can be attached before or after the map is shown; they fire on the next pause or camera change.

The blue dot uses the existing When In Use location permission. No new purpose string is required. Follow uses that same location stream. `followHeading` also reads the compass and rotates the map to the device heading. North-up follow (`followHeading: false`) recenters without rotating.

On iOS 16 and later the map uses realistic elevation (terrain and 3D buildings where Apple has modeled them, on A12 and newer). Older phones still get a pitched `MKMapView`, with flat terrain. Satellite is imagery. Hybrid is imagery plus labels and is the view that shows 3D buildings on top of satellite where Apple has them. The map uses dark mode so standard and muted sit next to the `#14110e` shell. Apple's own map chrome (legal line, compass) stays.

## Route and stops

Coordinates on the line are GeoJSON order: `[longitude, latitude]`. Stops are objects. You can also pass a stop or a line vertex as `{ lat, lng }` or `{ latitude, longitude }`.

```js
await tr3kNative.setRoute({
  coordinates: [[-83.987286, 34.0811107], [-83.9842244, 34.0710375]],
  stops: [
    { id: "1", name: "Stop 1", lat: 34.0811107, lng: -83.987286 }
  ],
  fit: false
});

await tr3kNative.clearRoute();
```

`fit: true` frames the line and stops, and keeps the current pitch. It does nothing while follow is on. Omit `coordinates` or `stops` to leave that layer alone. Pass `[]` to clear just one layer. Calling `setRoute` before `showMap` is fine; the overlay appears when the map is shown.

Stop pins use an orange marker and a callout with the stop name.

## Existing methods

These behaved the same way before the map work:

- `getLocation(opts)` → Geolocation-style position
- `watchLocation(onPos, onErr)` / `clearWatch(id)`
- `requestPermissions({ always })` → `{ location, alwaysPrompted, backgroundAlerts }`
- `requestNotifications()` → `{ granted }`
- `setStops(stops, { radius, title, body })` → `{ monitored, pending, supported, location, backgroundAlerts }`
- `clearStops()`
- `onArrival(cb)` → `{ stopId }`
- `setLiveDrop({ stopId, type, url, title?, unlockRadiusM? })` → `{ saved, stopId?, type?, reason? }`
- `setLiveDrops({ drops, replace })` / `getLiveDrop(stopId)` / `getLiveDrops()` / `clearLiveDrops({ stopId? })`
- `openXLiveDrop(url)` → `{ opened, url?, via?, reason? }`
- `onLiveDropUnlock(cb)` → `{ stopId, type, url, title?, demo, source, unlockId, issuedAt }`
- `previewLiveDrop({ stopId?, url?, type?, title? })` → `{ shown, stopId?, type?, demo? }`
- `share({ title, text, url })` → `{ completed }`
- `getLastDeepLink()` / `onDeepLink(cb)` and the `tr3kdeepLink` window event
- `haptic(kind)` → `{ played, kind }`
- `speak({ text, interrupt, mute, rate, lang })` → `{ spoken, id, queued?, reason? }`
- `stopSpeaking({ boundary? })` → `{ stopped, speaking }`
- `startLiveActivity({ trekId, trekName, stopName, stopIndex, stopCount, distanceText, etaText, action })` — also `questId`, `kind`, `progressText`, `phase`, `rare`
- `updateLiveActivity(partial)` / `endLiveActivity({ dismissal })` — `dismissal` `"immediate"` removes it now; `"default"` leaves a finished card for about 45 seconds
- `isARSupported()` / `arStatus()` / `openAR({ tier, prize })` / `openSettings()`
- `saveOfflineTreks({ key, v, at, nearby, active, lat, lng })` / `getOfflineTreks({ key })` / `clearOfflineTreks({ key })`
- `signInWithApple()` / `getAppleSession()` / `signOutApple()`

`navigator.geolocation` in the shell is still the native location stream.
