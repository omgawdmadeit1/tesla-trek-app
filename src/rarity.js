export function rarityColor(rarity) {
  switch (rarity) {
    case "common":
      return "#c4bfb4";
    case "rare":
      return "#2f6fbf";
    case "epic":
      return "#c9891a";
    case "legendary":
      return "#e25b2a";
    default: {
      const unknown = rarity;
      throw new Error(`Unknown rarity: ${String(unknown)}`);
    }
  }
}
