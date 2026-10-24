import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { activeStop, chooseCrackMode, distanceMeters, inRange, needsParkGate, rarityLabel } from "../src/logic.js";
import { TREK } from "../src/trek.js";

const root = new URL("..", import.meta.url).pathname;
let failed = 0;

function assert(condition, message) {
  if (!condition) {
    failed += 1;
    console.error(`FAIL ${message}`);
  }
}

assert(TREK.stops.length === 2, "launch trek has two stops");
assert(TREK.radiusMeters === 250, "pickup radius is 250 m");
assert(TREK.startsOn === "2026-10-24", "launch date is 2026-10-24");
for (const stop of TREK.stops) {
  assert(stop.placement === "public-sidewalk", `${stop.id} is marked public-sidewalk`);
  assert(stop.lat > 34.05 && stop.lat < 34.1, `${stop.id} latitude is in Buford`);
  assert(stop.lng < -83.96 && stop.lng > -84.0, `${stop.id} longitude is in Buford`);
}

assert(TREK.stops[0].lat === 34.0811107 && TREK.stops[0].lng === -83.987286, "stop 1 is the 3500 Buford Dr sidewalk");
assert(TREK.stops[1].lat === 34.0710375 && TREK.stops[1].lng === -83.9842244, "stop 2 is the mall sidewalk on Buford Dr");

const apart = distanceMeters(TREK.stops[0], TREK.stops[1]);
assert(apart > 700 && apart < 1600, `stops are distinct (${Math.round(apart)} m)`);

const near = { lat: TREK.stops[0].lat + 0.0004, lng: TREK.stops[0].lng };
const far = { lat: TREK.stops[0].lat + 0.01, lng: TREK.stops[0].lng };
assert(inRange(near, TREK.stops[0], TREK.radiusMeters), "nearby point is inside 250 m");
assert(!inRange(far, TREK.stops[0], TREK.radiusMeters), "distant point is outside 250 m");

assert(activeStop(TREK, {}).id === TREK.stops[0].id, "first stop is active");
assert(activeStop(TREK, { [TREK.stops[0].id]: {} }).id === TREK.stops[1].id, "second stop unlocks after the first");
assert(activeStop(TREK, { [TREK.stops[0].id]: {}, [TREK.stops[1].id]: {} }) === null, "trek completes");

assert(needsParkGate({ driving: true, speedMps: 0 }), "driving mode parks first");
assert(needsParkGate({ driving: false, speedMps: 8 }), "moving speed parks first");
assert(!needsParkGate({ driving: false, speedMps: 0 }), "standing still can crack");
assert(!needsParkGate({ driving: false, speedMps: null }), "unknown speed does not force the gate");

assert(chooseCrackMode({ platform: "ios", nativeAvailable: true, cameraGranted: false }) === "arkit", "iPhone uses ARKit");
assert(chooseCrackMode({ platform: "web", nativeAvailable: false, cameraGranted: true }) === "camera", "web uses the camera");
assert(chooseCrackMode({ platform: "ios", nativeAvailable: false, cameraGranted: false }) === "stage", "denied camera uses the stage");
assert(rarityLabel("epic") === "Epic", "epic label");
let threw = false;
try {
  rarityLabel("mythic");
} catch {
  threw = true;
}
assert(threw, "unknown rarity throws");

const config = readFileSync(join(root, "capacitor.config.json"), "utf8");
assert(config.includes('"appId": "app.tr3k.ios"'), "bundle id");
assert(config.includes('"appName": "Tr3k"'), "app name");

const plist = readFileSync(join(root, "ios/App/App/Info.plist"), "utf8");
assert(plist.includes("<string>location</string>"), "background location mode");
assert(plist.includes("<string>tr3k</string>"), "tr3k URL scheme");
assert(plist.includes("<key>NSSupportsLiveActivities</key>"), "Live Activities flag");
assert(plist.includes("Tr3k stop arrival"), "Always purpose mentions Tr3k stop arrival");

const entitlements = readFileSync(join(root, "ios/App/App/App.entitlements"), "utf8");
assert(entitlements.includes("applinks:tr3k.app"), "associated domain applinks:tr3k.app");

const shim = readFileSync(join(root, "plugins/tr3k-native/ios/Sources/Tr3kNativePlugin/Tr3kNativeShim.swift"), "utf8");
assert(shim.includes("version: 3"), "native shim version 3");
assert(shim.includes("tr3kdeepLink"), "deep link event name");

const nativeReadme = readFileSync(join(root, "plugins/tr3k-native/README.md"), "utf8");
assert(nativeReadme.includes("startLiveActivity"), "Live Activity is documented");
assert(nativeReadme.includes("https://tr3k.app/play/?trek=<id>"), "canonical Tr3k URL");
assert(nativeReadme.includes("haptic"), "haptics are documented");

const project = readFileSync(join(root, "ios/App/App.xcodeproj/project.pbxproj"), "utf8");
assert(project.includes("app.tr3k.ios.LiveActivity"), "Live Activity bundle id");
assert(project.includes("productName = Tr3kActivityKit"), "widget links Tr3kActivityKit");
assert(project.includes("CODE_SIGN_ENTITLEMENTS = App/App.entitlements;"), "app entitlements");
assert(project.includes("PRODUCT_BUNDLE_IDENTIFIER = app.tr3k.ios;"), "app bundle id");

const flight = readFileSync(join(root, "public/get/testflight.js"), "utf8");
assert(flight.includes("export const TESTFLIGHT_URL"), "TESTFLIGHT_URL constant");
assert(flight.includes("REPLACE_ME"), "TestFlight link is still a placeholder");

const skip = new Set(["node_modules", "dist", "ios", ".git", "build", "print"]);
const banned = new RegExp(
  ["tes", "la|fleet-", "api|super", "charger|\\b", "xy", "o\\b"].join(""),
  "i",
);

function walk(dir) {
  for (const name of readdirSync(dir)) {
    if (skip.has(name)) continue;
    const path = join(dir, name);
    const info = statSync(path);
    if (info.isDirectory()) {
      walk(path);
      continue;
    }
    if (!/\.(js|mjs|html|css|json|md|yml|yaml|swift|plist)$/.test(name)) continue;
    const text = readFileSync(path, "utf8");
    assert(!banned.test(text), `no retired branding in ${path.slice(root.length)}`);
  }
}

walk(root);

if (failed > 0) {
  console.error(`${failed} check(s) failed`);
  process.exit(1);
}
console.log(`checks passed (${Math.round(apart)} m between sidewalk pins)`);
