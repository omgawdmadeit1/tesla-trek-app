/**
 * Launch trek coordinates. Edit this file only.
 *
 * Saturday, October 24, 2026. Buford, Georgia.
 * Both pins sit on the public sidewalk along Buford Drive (GA 20),
 * not on a building footprint or a private lot.
 *
 * Stop 1 — 3500 Buford Dr frontage, west sidewalk.
 *   US Census Public AR Current places 3500 Buford Dr on the road
 *   centerline at 34.0811769, -83.9871607 (even address).
 *   The pin is the nearest point on the mapped sidewalk
 *   (OpenStreetMap way 1121251047), 14 m west of that centerline.
 *
 * Stop 2 — Mall of Georgia, 3333 Buford Dr, Buford, GA 30519.
 *   The pin is the sidewalk where the mall parcel meets Buford Drive
 *   (OpenStreetMap relation 11181195, sidewalk way 397665397),
 *   about 8 m from the road centerline. The mall's interior centroid
 *   is not used.
 *
 * Pickup radius is 250 m so a sidewalk, a parking row, or a passing
 * car can collect. Park before opening the cookie.
 */
export const TREK = {
  id: "buford-2026-10-24",
  name: "Buford Launch",
  startsOn: "2026-10-24",
  place: "Buford, Georgia",
  radiusMeters: 250,
  stops: [
    {
      id: "buford-dr-3500",
      name: "Buford Drive sidewalk",
      address: "3500 Buford Dr, Buford, GA 30519",
      detail:
        "Public sidewalk on the west side of Buford Drive, in front of the 3500 frontage.",
      lat: 34.0811107,
      lng: -83.987286,
      placement: "public-sidewalk",
      reward: {
        id: "buford-mile-keychain",
        name: "Buford Mile keychain",
        rarity: "rare",
        kind: "keychain",
      },
    },
    {
      id: "mall-of-georgia-sidewalk",
      name: "Mall of Georgia sidewalk",
      address: "3333 Buford Dr, Buford, GA 30519",
      detail:
        "Public sidewalk on Buford Drive where Mall of Georgia meets the road.",
      lat: 34.0710375,
      lng: -83.9842244,
      placement: "public-sidewalk",
      reward: {
        id: "launch-night-skin",
        name: "Launch night skin",
        rarity: "epic",
        kind: "skin",
      },
    },
  ],
};

export const TESTFLIGHT_PLACEHOLDER = "REPLACE_ME";

/**
 * X Live Drop for one stop. Set `url` to a Space or Chat link when one exists.
 * Leave it empty for the Internal demo: the phone opens the X app with no
 * Space id and no token. `type` is "space" or "chat".
 */
export const LIVE_DROP = {
  stopId: "buford-dr-3500",
  type: "space",
  url: "",
  title: "Live",
  unlockRadiusM: 75,
};
