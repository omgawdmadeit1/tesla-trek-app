# Tr3k native bridge

iOS-only Capacitor plugin (`jsName` `Tr3kNative`). The shell injects `window.tr3kNative` at document start on every page, including `https://tr3k.app/play/`. Shim version is `window.tr3kNative.version` (currently **3**).

Version 2 is the MapKit map (`MKMapCamera` pitch and Apple's 3D buildings). The browser keeps its own map. This plugin does not load MapKit JS and does not need a MapKit token.

Version 3 adds three product paths on the same object: background Tr3k stop arrival alerts, the share sheet plus deep links, and haptics plus a local Live Activity. Map, location watch, and `openAR` stay as they were.

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

`UIBackgroundModes` includes `location` so those region events can wake the app. The shell does not keep the GPS radio on in the background; follow and `watchLocation` pause until Tr3k is open again.

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

Also accepted: `heavy`, `soft`, `rigid`, `error`, `selection`. An unknown kind resolves `{ played: false, kind }` and does not throw. `haptic({ kind: "success" })` works too. These are impact and notification generators on the phone. The web nav loop should call them; the native arrival notification does not vibrate by itself.

## Live Activity

Local ActivityKit activity for the navigation that is already on screen. No push token and no push-to-start. The Lock Screen and Dynamic Island show the latest instruction, distance, and ETA. Updates only happen while the web nav loop is running (the app in the foreground). The last content stays up after you leave the app until `endLiveActivity`.

```js
const started = await tr3kNative.startLiveActivity({
  trekId: "buford",
  trekName: "Buford",
  instruction: "Continue on Buford Dr",
  distanceText: "400 m",
  etaText: "5 min",
  stopName: "Stop 1"
});
// started.started is false with reason "unsupported" below iOS 16.2
// or "disabled" when Live Activities are off in Settings

await tr3kNative.updateLiveActivity({
  instruction: "Turn left",
  distanceText: "80 m",
  etaText: "1 min"
});

await tr3kNative.endLiveActivity();                  // dismissal: "immediate"
await tr3kNative.endLiveActivity({ dismissal: "default" });
```

`distance` and `eta` are accepted aliases of `distanceText` and `etaText`. Omitted fields keep the previous text. `trekName` defaults to "Tr3k".

The widget extension bundle id is `app.tr3k.ios.LiveActivity`. It links the `Tr3kActivityKit` module, which is also what the shell uses, so the activity type matches. The app Info.plist key `NSSupportsLiveActivities` is true. There is no Push Notifications capability. iOS 15 still installs; `startLiveActivity` resolves `unsupported` there.

Joseph: the TestFlight lane registers `app.tr3k.ios.LiveActivity` and requests an App Store profile for it. If that step fails, create that bundle id on team `DQA38RTNF7`. Local Live Activities do not need a separate portal capability beyond the Info.plist flag. If a future Apple portal toggle appears for Live Activities on `app.tr3k.ios`, turn it on. Do not enable push for this.

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
- `share({ title, text, url })` → `{ completed }`
- `getLastDeepLink()` / `onDeepLink(cb)` and the `tr3kdeepLink` window event
- `haptic(kind)` → `{ played, kind }`
- `startLiveActivity({ trekId, trekName, instruction, distanceText, etaText, stopName })`
- `updateLiveActivity(partial)` / `endLiveActivity({ dismissal })`
- `isARSupported()` / `openAR({ tier, prize })`

`navigator.geolocation` in the shell is still the native location stream.
