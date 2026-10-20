import { Capacitor, registerPlugin } from "@capacitor/core";

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
