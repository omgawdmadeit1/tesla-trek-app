import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { activeStop, chooseCrackMode, distanceMeters, inRange, needsParkGate, rarityLabel } from "../src/logic.js";
import { joinLabel, liveDropHeadline, resolveLiveDrop } from "../src/live-drop.js";
import { LIVE_DROP, TREK } from "../src/trek.js";

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
assert(plist.includes("<string>audio</string>"), "background audio mode for spoken directions");
assert(plist.includes("<string>tr3k</string>"), "tr3k URL scheme");
assert(plist.includes("<key>LSApplicationQueriesSchemes</key>"), "X app query schemes");
assert(plist.includes("<string>twitter</string>"), "twitter query scheme");
assert(plist.includes("<string>x</string>"), "x query scheme");
assert(plist.includes("<key>NSSupportsLiveActivities</key>"), "Live Activities flag");
assert(plist.includes("Tr3k stop arrival"), "Always purpose mentions Tr3k stop arrival");

assert(plist.includes("fortune cookie"), "camera purpose mentions the fortune cookie");
assert(plist.includes("glowing pumpkin"), "camera purpose mentions the glowing pumpkin");
assert(plist.includes("AR collectible"), "motion purpose mentions the AR collectible");

const entitlements = readFileSync(join(root, "ios/App/App/App.entitlements"), "utf8");
assert(entitlements.includes("applinks:tr3k.app"), "associated domain applinks:tr3k.app");
assert(entitlements.includes("group.app.tr3k.ios"), "app group on the app");
assert(entitlements.includes("com.apple.developer.applesignin"), "Sign in with Apple entitlement");

const widgetEntitlements = readFileSync(join(root, "ios/App/Tr3kWidget/Tr3kWidget.entitlements"), "utf8");
assert(widgetEntitlements.includes("group.app.tr3k.ios"), "app group on the widget");

const widgetPlist = readFileSync(join(root, "ios/App/Tr3kWidget/Info.plist"), "utf8");
assert(widgetPlist.includes("com.apple.widgetkit-extension"), "home screen widget extension point");
assert(widgetPlist.includes("NSLocationWhenInUseUsageDescription"), "widget location purpose");

const widgetSwift = readFileSync(join(root, "ios/App/Tr3kWidget/Tr3kWidget.swift"), "utf8");
assert(widgetSwift.includes("Enable location for nearby Tr3ks"), "widget location prompt");
assert(widgetSwift.includes("byAdding: .hour"), "widget hourly timeline");
assert(widgetSwift.includes("primaryLink"), "widget tap uses the shared link");

const nearbyFeed = readFileSync(join(root, "plugins/tr3k-native/ios/Sources/Tr3kAppGroup/Tr3kNearbyFeed.swift"), "utf8");
assert(nearbyFeed.includes("https://tr3k.app/api/nearby"), "widget uses the nearby API");

const shim = readFileSync(join(root, "plugins/tr3k-native/ios/Sources/Tr3kNativePlugin/Tr3kNativeShim.swift"), "utf8");
assert(shim.includes("version: 6"), "native shim version 6");
assert(!shim.includes("version: 5"), "shim version is no longer 5");
assert(!shim.includes("version: 4"), "shim version is no longer 4");
assert(shim.includes("speak: function"), "speak");
assert(shim.includes("stopSpeaking: function"), "stopSpeaking");
assert(shim.includes("setLiveDrop:"), "setLiveDrop");
assert(shim.includes("openXLiveDrop:"), "openXLiveDrop");
assert(shim.includes("onLiveDropUnlock:"), "onLiveDropUnlock");
assert(shim.includes("previewLiveDrop:"), "previewLiveDrop");
assert(shim.includes("liveDropUnlock"), "live drop event name");
assert(shim.includes("tr3knativeready"), "native ready event");
assert(shim.includes("tr3kdeepLink"), "deep link event name");
assert(shim.includes("saveOfflineTreks:"), "saveOfflineTreks");
assert(shim.includes("saveOffline:"), "saveOffline alias");
assert(shim.includes("offlineSave:"), "offlineSave alias");
assert(shim.includes("getOfflineTreks:"), "getOfflineTreks");
assert(shim.includes("getOffline:"), "getOffline alias");
assert(shim.includes("offlineGet:"), "offlineGet alias");
assert(shim.includes("clearOfflineTreks:"), "clearOfflineTreks");
assert(shim.includes("clearOffline:"), "clearOffline alias");
assert(shim.includes("offlineClear:"), "offlineClear alias");
assert(shim.includes("signInWithApple:"), "signInWithApple");
assert(shim.includes("getAppleSession:"), "getAppleSession");
assert(shim.includes("signOutApple:"), "signOutApple");
assert(shim.includes("openSettings:"), "openSettings");
assert(shim.includes("arStatus:"), "arStatus");

const nativeReadme = readFileSync(join(root, "plugins/tr3k-native/README.md"), "utf8");
assert(nativeReadme.includes("currently **6**"), "shim version 6 is documented");
assert(nativeReadme.includes("tr3kNative.speak"), "speak is documented");
assert(nativeReadme.includes("stopSpeaking"), "stopSpeaking is documented");
assert(nativeReadme.includes("UIBackgroundModes"), "background modes are documented");
assert(nativeReadme.includes("`audio`"), "audio background mode is documented");
assert(nativeReadme.includes("openXLiveDrop"), "X Live Drop is documented");
assert(nativeReadme.includes("onLiveDropUnlock"), "live drop unlock is documented");
assert(nativeReadme.includes("Only people at this stop."), "live drop microcopy is documented");
assert(nativeReadme.includes("startLiveActivity"), "Live Activity is documented");
assert(nativeReadme.includes("JOIN Live Drop"), "live drop action is documented");
assert(nativeReadme.includes("Hunt AR"), "hunt action is documented");
assert(nativeReadme.includes("2/4"), "stop progress is documented");
assert(nativeReadme.includes("https://tr3k.app/play/?trek=<id>"), "canonical Tr3k URL");
assert(nativeReadme.includes("haptic"), "haptics are documented");
assert(nativeReadme.includes("saveOfflineTreks"), "offline save is documented");
assert(nativeReadme.includes("getOfflineTreks"), "offline get is documented");
assert(nativeReadme.includes("clearOfflineTreks"), "offline clear is documented");
assert(nativeReadme.includes("signInWithApple"), "Sign in with Apple is documented");
assert(nativeReadme.includes("group.app.tr3k.ios"), "app group is documented");
assert(nativeReadme.includes("Enable location for nearby Tr3ks"), "widget prompt is documented");
assert(nativeReadme.includes("/api/nearby"), "nearby API is documented for the widget");

const project = readFileSync(join(root, "ios/App/App.xcodeproj/project.pbxproj"), "utf8");
assert(project.includes("app.tr3k.ios.LiveActivity"), "Live Activity bundle id");
const liveActivity = readFileSync(join(root, "ios/App/Tr3kLiveActivity/Tr3kLiveActivity.swift"), "utf8");
const liveCopy = readFileSync(join(root, "plugins/tr3k-native/ios/Sources/Tr3kActivityKit/Tr3kNavigationAttributes.swift"), "utf8");
const liveMirror = readFileSync(join(root, "plugins/tr3k-native/ios/Sources/Tr3kNativePlugin/Tr3kLiveActivityMirror.swift"), "utf8");
assert(liveActivity.includes("widgetURL"), "Live Activity tap opens the trek");
assert(liveActivity.includes("activityBackgroundTint"), "Live Activity keeps a black field");
assert(liveCopy.includes("https://tr3k.app/play/"), "Live Activity uses the play universal link");
assert(liveCopy.includes("JOIN Live Drop"), "join action copy");
assert(liveCopy.includes("Hunt AR"), "hunt action copy");
assert(liveMirror.includes("noteArrival"), "arrival updates the Live Activity");
assert(liveMirror.includes("noteSpeech"), "spoken steps update the Live Activity");
assert(shim.includes("startLiveActivity"), "existing Live Activity bridge");
assert(project.includes("app.tr3k.ios.widget"), "home screen widget bundle id");
assert(project.includes("productName = Tr3kActivityKit"), "Live Activity links Tr3kActivityKit");
assert(project.includes("productName = Tr3kAppGroup"), "widget links Tr3kAppGroup");
assert(project.includes("CODE_SIGN_ENTITLEMENTS = App/App.entitlements;"), "app entitlements");
assert(project.includes("PRODUCT_BUNDLE_IDENTIFIER = app.tr3k.ios;"), "app bundle id");

const nativePackage = readFileSync(join(root, "plugins/tr3k-native/Package.swift"), "utf8");
assert(nativePackage.includes("-disable-autolink-framework"), "ActivityKit stays weakly linked");
assert(nativePackage.includes("\"-weak_framework\", \"ActivityKit\""), "ActivityKit weak framework flag");

const liveDropJs = readFileSync(join(root, "src/live-drop.js"), "utf8");
const liveDropSwift = readFileSync(join(root, "plugins/tr3k-native/ios/Sources/Tr3kNativePlugin/Tr3kLiveDrop.swift"), "utf8");
const patchIos = readFileSync(join(root, "scripts/patch-ios.mjs"), "utf8");
assert(patchIos.includes("LSApplicationQueriesSchemes"), "patch keeps X query schemes");
assert(liveDropSwift.includes(joinLabel("space")), "native space label matches");
assert(liveDropSwift.includes(joinLabel("chat")), "native chat label matches");
assert(liveDropSwift.includes("Only people at this stop."), "native note matches");
assert(liveDropSwift.includes("x://spaces/"), "space deep link");
assert(liveDropSwift.includes("twitter://spaces/"), "legacy space deep link");
assert(liveDropSwift.includes("https://x.com/i/spaces/"), "space https fallback");
assert(liveDropJs.includes("Only people at this stop."), "web note matches");

assert(LIVE_DROP.stopId === TREK.stops[0].id, "live drop is armed on stop 1");
assert(LIVE_DROP.url === "", "live drop url ships empty");
assert(LIVE_DROP.type === "space", "launch live drop is a space");
assert(LIVE_DROP.unlockRadiusM === 75, "live drop radius is 75 m");

const demo = resolveLiveDrop(LIVE_DROP);
assert(demo && demo.demo === true, "empty url is a demo drop");
assert(demo.url === "https://x.com/i/spaces", "demo space url");
assert(demo.type === "space", "demo type");
assert(joinLabel("space") === "JOIN 𝕏 SPACE", "space label");
assert(joinLabel("chat") === "JOIN 𝕏 CHAT", "chat label");
assert(liveDropHeadline("Live") === "LIVE", "short title becomes the headline");
assert(liveDropHeadline("") === "LIVE", "missing title is LIVE");
const chatDemo = resolveLiveDrop({ stopId: "buford-dr-3500", type: "chat", url: "" });
assert(chatDemo && chatDemo.url === "https://x.com/messages", "demo chat url");
const real = resolveLiveDrop({
  stopId: "buford-dr-3500",
  type: "space",
  url: "https://x.com/i/spaces/abc123",
  title: "Live",
  unlockRadiusM: 75,
});
assert(real && real.demo === false && real.url === "https://x.com/i/spaces/abc123", "configured space url is kept");
assert(resolveLiveDrop({ stopId: "buford-dr-3500", type: "space", url: "https://evil.example/spaces/abc" }) === null, "non-X url is rejected");
assert(resolveLiveDrop({ stopId: "", type: "space", url: "" }) === null, "missing stop id is rejected");

const fastfile = readFileSync(join(root, "fastlane/Fastfile"), "utf8");
assert(fastfile.includes("app.tr3k.ios.widget"), "widget bundle id in the signing lane");
assert(fastfile.includes("tr3k-widget-appstore"), "widget provisioning profile name");
assert(fastfile.includes("APPLE_ID_AUTH"), "Sign in with Apple capability");
assert(fastfile.includes("group.app.tr3k.ios"), "app group in the signing lane");
assert(!fastfile.includes("skip_waiting_for_build_processing: false"), "TestFlight still skips waiting");

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
