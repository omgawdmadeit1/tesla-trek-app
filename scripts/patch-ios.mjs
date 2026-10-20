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
  "Tr3k uses the camera to place a fortune cookie in front of you and crack it open.",
);
setString(
  "NSLocationWhenInUseUsageDescription",
  "Tr3k uses your location to check you in when you reach a trek stop.",
);
setString(
  "NSMotionUsageDescription",
  "Tr3k uses motion so the cookie stays put while you look around.",
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
console.log("patched iOS display name, permissions, bundle id, and team");
