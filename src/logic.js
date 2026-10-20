const EARTH_RADIUS_M = 6371000;
const MOVING_MPS = 4.5;

export function distanceMeters(a, b) {
  const p1 = (a.lat * Math.PI) / 180;
  const p2 = (b.lat * Math.PI) / 180;
  const dPhi = ((b.lat - a.lat) * Math.PI) / 180;
  const dLambda = ((b.lng - a.lng) * Math.PI) / 180;
  const h =
    Math.sin(dPhi / 2) ** 2 +
    Math.cos(p1) * Math.cos(p2) * Math.sin(dLambda / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

export function inRange(user, stop, radiusMeters) {
  if (!user) return false;
  return distanceMeters(user, stop) <= radiusMeters;
}

export function activeStop(trek, collected) {
  return trek.stops.find((stop) => !collected[stop.id]) ?? null;
}

export function needsParkGate({ driving, speedMps }) {
  if (driving) return true;
  return typeof speedMps === "number" && Number.isFinite(speedMps) && speedMps > MOVING_MPS;
}

/**
 * @param {"ios" | "web" | "android"} platform
 * @param {boolean} nativeAvailable
 * @param {boolean} cameraGranted
 * @returns {"arkit" | "camera" | "stage"}
 */
export function chooseCrackMode({ platform, nativeAvailable, cameraGranted }) {
  if (platform === "ios" && nativeAvailable) return "arkit";
  if (cameraGranted) return "camera";
  return "stage";
}

export function rarityLabel(rarity) {
  switch (rarity) {
    case "common":
      return "Common";
    case "rare":
      return "Rare";
    case "epic":
      return "Epic";
    case "legendary":
      return "Legendary";
    default: {
      const unknown = rarity;
      throw new Error(`Unknown rarity: ${String(unknown)}`);
    }
  }
}

export function formatDistance(meters) {
  if (!Number.isFinite(meters)) return "Distance unknown";
  if (meters < 1000) return `${Math.round(meters)} m away`;
  return `${(meters / 1000).toFixed(1)} km away`;
}
