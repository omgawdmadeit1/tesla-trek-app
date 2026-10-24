import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const plistPath = join(root, "ios/App/App/Info.plist");
const projectPath = join(root, "ios/App/App.xcodeproj/project.pbxproj");

if (!existsSync(plistPath) || !existsSync(projectPath)) {
  console.error("iOS project is missing. Run npx cap add ios first.");
  process.exit(1);
}

let plist = readFileSync(plistPath, "utf8");

function setString(key, value) {
  const pattern = new RegExp(`<key>${key}</key>\\s*<string>[\\s\\S]*?</string>`);
  const block = `<key>${key}</key>\n\t<string>${value}</string>`;
  if (pattern.test(plist)) plist = plist.replace(pattern, block);
  else plist = plist.replace("</dict>\n</plist>", `\t${block}\n</dict>\n</plist>`);
}

function setBool(key, value) {
  const pattern = new RegExp(`<key>${key}</key>\\s*<(?:true|false)/>`);
  const block = `<key>${key}</key>\n\t<${value}/>`;
  if (pattern.test(plist)) plist = plist.replace(pattern, block);
  else plist = plist.replace("</dict>\n</plist>", `\t${block}\n</dict>\n</plist>`);
}

setString("CFBundleDisplayName", "Tr3k");
setString(
  "NSCameraUsageDescription",
  "Tr3k uses the camera to place an AR collectible in front of you, a fortune cookie or a glowing pumpkin, so you can open it. Nothing is recorded or uploaded.",
);
setString(
  "NSLocationWhenInUseUsageDescription",
  "Tr3k uses your precise location to show nearby treasure hunts, give turn-by-turn directions, and confirm you have reached each Tr3k stop.",
);
setString(
  "NSLocationAlwaysAndWhenInUseUsageDescription",
  "Tr3k uses your location in the background to send Tr3k stop arrival alerts when you reach a stop on your current hunt, even if Tr3k is not open. Tr3k only watches the stops on that hunt.",
);
setString(
  "NSMotionUsageDescription",
  "Tr3k uses motion so the AR collectible, the fortune cookie or pumpkin, stays in place while you look around.",
);
setBool("ITSAppUsesNonExemptEncryption", "false");
setBool("NSSupportsLiveActivities", "true");

if (!plist.includes("<key>UIBackgroundModes</key>")) {
  plist = plist.replace(
    "</dict>\n</plist>",
    "\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>location</string>\n\t</array>\n</dict>\n</plist>",
  );
} else if (!plist.includes("<string>location</string>")) {
  plist = plist.replace(
    "<key>UIBackgroundModes</key>\n\t<array>",
    "<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>location</string>",
  );
}

if (!plist.includes("<key>LSApplicationQueriesSchemes</key>")) {
  plist = plist.replace(
    "</dict>\n</plist>",
    `\t<key>LSApplicationQueriesSchemes</key>
\t<array>
\t\t<string>twitter</string>
\t\t<string>x</string>
\t</array>
</dict>
</plist>`,
  );
} else {
  if (!plist.includes("<string>twitter</string>")) {
    plist = plist.replace(
      "<key>LSApplicationQueriesSchemes</key>\n\t<array>",
      "<key>LSApplicationQueriesSchemes</key>\n\t<array>\n\t\t<string>twitter</string>",
    );
  }
  if (!plist.includes("<string>x</string>")) {
    plist = plist.replace(
      "<key>LSApplicationQueriesSchemes</key>\n\t<array>",
      "<key>LSApplicationQueriesSchemes</key>\n\t<array>\n\t\t<string>x</string>",
    );
  }
}

if (!plist.includes("<string>tr3k</string>")) {
  plist = plist.replace(
    "</dict>\n</plist>",
    `\t<key>CFBundleURLTypes</key>
\t<array>
\t\t<dict>
\t\t\t<key>CFBundleURLName</key>
\t\t\t<string>app.tr3k.ios</string>
\t\t\t<key>CFBundleURLSchemes</key>
\t\t\t<array>
\t\t\t\t<string>tr3k</string>
\t\t\t</array>
\t\t</dict>
\t</array>
</dict>
</plist>`,
  );
}
writeFileSync(plistPath, plist);

const entitlementsPath = join(root, "ios/App/App/App.entitlements");
const entitlements = existsSync(entitlementsPath) ? readFileSync(entitlementsPath, "utf8") : "";
const entitlementKeys = [
  "applinks:tr3k.app",
  "group.app.tr3k.ios",
  "com.apple.developer.applesignin",
];
if (entitlementKeys.some((key) => !entitlements.includes(key))) {
  writeFileSync(
    entitlementsPath,
    `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.developer.applesignin</key>
\t<array>
\t\t<string>Default</string>
\t</array>
\t<key>com.apple.developer.associated-domains</key>
\t<array>
\t\t<string>applinks:tr3k.app</string>
\t</array>
\t<key>com.apple.security.application-groups</key>
\t<array>
\t\t<string>group.app.tr3k.ios</string>
\t</array>
</dict>
</plist>
`,
  );
}

let project = readFileSync(projectPath, "utf8");
project = project.replace(/PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/g, (match, value) => {
  const id = value.trim();
  if (id === "app.tr3k.ios" || id.startsWith("app.tr3k.ios.")) return match;
  return "PRODUCT_BUNDLE_IDENTIFIER = app.tr3k.ios;";
});
if (!project.includes("DEVELOPMENT_TEAM = DQA38RTNF7;")) {
  project = project.replaceAll(
    "PRODUCT_BUNDLE_IDENTIFIER = app.tr3k.ios;",
    "PRODUCT_BUNDLE_IDENTIFIER = app.tr3k.ios;\n\t\t\t\tDEVELOPMENT_TEAM = DQA38RTNF7;",
  );
}
if (!project.includes("CODE_SIGN_ENTITLEMENTS = App/App.entitlements;")) {
  project = project.replaceAll(
    "PRODUCT_BUNDLE_IDENTIFIER = app.tr3k.ios;",
    "CODE_SIGN_ENTITLEMENTS = App/App.entitlements;\n\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = app.tr3k.ios;",
  );
}
writeFileSync(projectPath, project);
console.log("patched iOS display name, permissions, arrival alerts, links, Live Activity, widget, bundle id, and team");
