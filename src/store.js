const KEY = "tr3k.buford.v1";

export function emptyState() {
  return { driving: false, collected: {} };
}

export function loadState() {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return emptyState();
    const parsed = JSON.parse(raw);
    return {
      driving: Boolean(parsed.driving),
      collected: parsed.collected && typeof parsed.collected === "object" ? parsed.collected : {},
    };
  } catch {
    return emptyState();
  }
}

export function saveState(state) {
  localStorage.setItem(KEY, JSON.stringify(state));
}
