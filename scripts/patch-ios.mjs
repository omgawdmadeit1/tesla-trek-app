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
  "Allow Tr3k to use your location in the background so it can alert you the moment you arrive at a Tr3k stop, even when the app is closed. Tr3k only watches for the stops on your current hunt.",
);
setString(
  "NSMotionUsageDescription",
  "Tr3k uses your phone's motion sensors so the treasure stays in place while you look around in AR.",
);
setBool("ITSAppUsesNonExemptEncryption", "false");
writeFileSync(plistPath, plist);

let project = readFileSync(projectPath, "utf8");
project = project.replaceAll(/PRODUCT_BUNDLE_IDENTIFIER = [^;]+;/g, "PRODUCT_BUNDLE_IDENTIFIER = app.tr3k.ios;");
if (!project.includes("DEVELOPMENT_TEAM = DQA38RTNF7;")) {
  project = project.replaceAll(
    "PRODUCT_BUNDLE_IDENTIFIER = app.tr3k.ios;",
    "PRODUCT_BUNDLE_IDENTIFIER = app.tr3k.ios;\n\t\t\t\tDEVELOPMENT_TEAM = DQA38RTNF7;",
  );
}
writeFileSync(projectPath, project);
console.log("patched iOS display name, permissions, arrival notifications, bundle id, and team");
