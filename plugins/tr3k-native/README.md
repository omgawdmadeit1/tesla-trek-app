# Tr3k native bridge

iOS-only Capacitor plugin (`jsName` `Tr3kNative`). The shell injects `window.tr3kNative` at document start on every page, including `https://tr3k.app/play/`. Shim version is `window.tr3kNative.version` (currently **2**).

Location, stop-arrival alerts, and `openAR` are unchanged. Version 2 adds a real MapKit map so in-Tr3k navigation can use `MKMapCamera` pitch and Apple's 3D buildings. The browser keeps its own map. This plugin does not load MapKit JS and does not need a MapKit token.

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
- `requestPermissions({ always })`
- `requestNotifications()`
- `setStops(stops, { radius, title, body })` / `clearStops()`
- `onArrival(cb)` → `{ stopId }`
- `isARSupported()` / `openAR({ tier, prize })`

`navigator.geolocation` in the shell is still the native location stream.
