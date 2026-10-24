const DEMO_SPACE = "https://x.com/i/spaces";
const DEMO_CHAT = "https://x.com/messages";
const NOTE = "Only people at this stop.";

function isXUrl(value) {
  return /^(https:\/\/(www\.)?(x\.com|twitter\.com|mobile\.twitter\.com|mobile\.x\.com)\/|x:\/\/|twitter:\/\/)/i.test(value);
}

// Slim drop the bridge will store. Empty `url` is the Internal demo handoff
// (X Spaces or Messages home). No token, no Space id.
export function resolveLiveDrop(config) {
  if (!config || typeof config !== "object") return null;
  const stopId = String(config.stopId || "").trim();
  if (!/^[A-Za-z0-9._-]{1,128}$/.test(stopId)) return null;
  const type = config.type === "chat" ? "chat" : "space";
  const configured = String(config.url || config.deepLink || "").trim();
  const demo = configured.length === 0;
  const url = demo ? (type === "chat" ? DEMO_CHAT : DEMO_SPACE) : configured;
  if (!demo && !isXUrl(url)) return null;
  const drop = { stopId, type, url, demo };
  if (config.title != null && String(config.title).trim()) {
    const title = String(config.title).replace(/\s+/g, " ").trim().slice(0, 80);
    if (title) drop.title = title;
  }
  const radius = Number(config.unlockRadiusM);
  if (Number.isFinite(radius)) drop.unlockRadiusM = Math.min(500, Math.max(15, radius));
  return drop;
}

export function joinLabel(type) {
  return type === "chat" ? "JOIN 𝕏 CHAT" : "JOIN 𝕏 SPACE";
}

export function liveDropHeadline(title) {
  const trimmed = String(title || "").replace(/\s+/g, " ").trim();
  if (!trimmed) return "LIVE";
  if ([...trimmed].length <= 16) return trimmed.toLocaleUpperCase("en-US");
  return trimmed;
}

export function bindLiveDrop(options) {
  if (typeof document === "undefined") return;
  const payload = resolveLiveDrop(options && options.drop);
  const stops = (options && options.stops) || [];
  const onShow = options && options.onShow;
  const onHide = options && options.onHide;

  const root = document.createElement("section");
  root.id = "x-live";
  root.hidden = true;
  root.setAttribute("role", "dialog");
  root.setAttribute("aria-modal", "true");
  root.setAttribute("aria-labelledby", "x-live-title");
  root.innerHTML = `<h1 id="x-live-title"></h1><button type="button" data-join></button><p></p>`;
  document.body.appendChild(root);
  const titleEl = root.querySelector("#x-live-title");
  const button = root.querySelector("[data-join]");
  const noteEl = root.querySelector("p");
  noteEl.textContent = NOTE;

  function show(event) {
    const type = event && event.type === "chat" ? "chat" : "space";
    const url = (event && event.url) || (payload && payload.url) || (type === "chat" ? DEMO_CHAT : DEMO_SPACE);
    titleEl.textContent = liveDropHeadline(event && event.title);
    button.textContent = joinLabel(type);
    root.dataset.url = url;
    root.hidden = false;
    if (onShow) onShow();
    button.focus();
  }

  function hide() {
    if (root.hidden) return;
    root.hidden = true;
    if (onHide) onHide();
  }

  button.addEventListener("click", async () => {
    const url = root.dataset.url;
    const bridge = window.tr3kNative;
    if (bridge && typeof bridge.openXLiveDrop === "function") {
      try {
        const result = await bridge.openXLiveDrop(url);
        if (result && result.opened) {
          hide();
          return;
        }
      } catch {
        // Fall through to the https link.
      }
    }
    if (url) window.location.assign(url);
    hide();
  });

  let startY = 0;
  root.addEventListener("touchstart", (event) => {
    if (event.target.closest("button")) return;
    startY = event.changedTouches[0].clientY;
  }, { passive: true });
  root.addEventListener("touchend", (event) => {
    if (event.target.closest("button")) return;
    if (event.changedTouches[0].clientY - startY > 80) hide();
  }, { passive: true });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !root.hidden) hide();
  });

  function arm(bridge) {
    if (!bridge) return;
    if (payload && typeof bridge.setLiveDrop === "function") {
      bridge.setLiveDrop(payload).catch(() => {});
    }
    if (typeof bridge.onLiveDropUnlock === "function") {
      bridge.onLiveDropUnlock((event) => show(event || payload));
    }
    if (stops.length && typeof bridge.setStops === "function") {
      const radius = (payload && payload.unlockRadiusM) || 75;
      Promise.resolve()
        .then(() => (typeof bridge.requestPermissions === "function" ? bridge.requestPermissions({ always: true }) : null))
        .catch(() => {})
        .then(() => (typeof bridge.requestNotifications === "function" ? bridge.requestNotifications() : null))
        .catch(() => {})
        .then(() => bridge.setStops(stops, { radius }))
        .catch(() => {});
    }
  }

  function ready() {
    arm(window.tr3kNative);
  }
  if (window.tr3kNative) ready();
  else window.addEventListener("tr3knativeready", ready, { once: true });

  const params = new URLSearchParams(window.location.search);
  if (params.has("liveDrop")) {
    const flag = params.get("liveDrop") || "";
    const base = payload || { stopId: "demo", type: "space", url: DEMO_SPACE, title: "Live", demo: true };
    let preview = { ...base };
    if (flag.includes("://")) {
      const parsed = resolveLiveDrop({
        stopId: base.stopId,
        type: params.get("liveDropType") || base.type,
        url: flag,
        title: base.title,
      });
      if (parsed) preview = parsed;
    } else if ((params.get("liveDropType") || preview.type) === "chat") {
      preview = { ...preview, type: "chat" };
      if (preview.demo || !preview.url) preview.url = DEMO_CHAT;
    }
    show(preview);
  }
}
