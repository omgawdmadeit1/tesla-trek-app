import { Capacitor, registerPlugin } from "@capacitor/core";

// Shell page at tr3k.app/play uses window.tr3kNative (shim v4). This plugin is the
// fortune-cookie path: open() adds camera, supported, canOpenSettings, and message.
// Call Tr3kAR.openSettings() when canOpenSettings is true. Nothing here is required
// for the hosted play page.
const Tr3kAR = registerPlugin("Tr3kAR");

export async function nativeCrackAvailable() {
  if (Capacitor.getPlatform() !== "ios") return false;
  try {
    const result = await Tr3kAR.isAvailable();
    return Boolean(result?.available);
  } catch {
    return false;
  }
}

export async function openNativeCrack(reward) {
  return Tr3kAR.open({
    rewardName: reward.name,
    rarity: reward.rarity,
    kind: reward.kind,
  });
}
