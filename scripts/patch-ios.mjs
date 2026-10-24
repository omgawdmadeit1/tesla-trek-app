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
  "Tr3k uses your camera to place a glowing pumpkin box in front of you so you can open your prize. Nothing is recorded or uploaded.",
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
  "Tr3k uses your phone's motion sensors so the treasure stays in place while you look around in AR.",
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
if (!existsSync(entitlementsPath) || !readFileSync(entitlementsPath, "utf8").includes("applinks:tr3k.app")) {
  writeFileSync(
    entitlementsPath,
    `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.developer.associated-domains</key>
\t<array>
\t\t<string>applinks:tr3k.app</string>
\t</array>
</dict>
</plist>
`,
  );
}

let project = readFileSync(projectPath, "utf8");
project = project.replace(/PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/g, (match, value) => {
  if (value.trim() === "app.tr3k.ios.LiveActivity") return match;
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
console.log("patched iOS display name, permissions, arrival alerts, links, Live Activity, bundle id, and team");
