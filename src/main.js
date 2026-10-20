import { Geolocation } from "@capacitor/geolocation";
import { StatusBar, Style } from "@capacitor/status-bar";
import { runCrack } from "./ar-web.js";
import { activeStop, distanceMeters, formatDistance, inRange, needsParkGate, rarityLabel } from "./logic.js";
import { mountMap } from "./map-view.js";
import { rarityColor } from "./rarity.js";
import { loadState, saveState } from "./store.js";
import { TREK } from "./trek.js";

const state = loadState();
let user = null;
let speedMps = null;
let pending = null;
let watchId = null;

const mapHost = document.querySelector("#map");
const sheet = document.querySelector("#sheet");
const pack = document.querySelector("#pack");
const park = document.querySelector("#park");
const reveal = document.querySelector("#reveal");
const toastEl = document.querySelector("#toast");
const driveBtn = document.querySelector("#drive");
const locateBtn = document.querySelector("#locate");
const tabTrek = document.querySelector("#tab-trek");
const tabPack = document.querySelector("#tab-pack");

const mapView = mountMap(mapHost, TREK);

StatusBar.setStyle({ style: Style.Dark }).catch(() => {});

driveBtn.addEventListener("click", () => {
  state.driving = !state.driving;
  saveState(state);
  render();
});

locateBtn.addEventListener("click", () => {
  startWatch().catch(() => toast("Location is off. Demo mode still finishes the trek."));
});

tabTrek.addEventListener("click", () => show("trek"));
tabPack.addEventListener("click", () => show("pack"));

document.querySelector("#parked").addEventListener("click", () => {
  window.speechSynthesis?.cancel();
  const next = pending;
  pending = null;
  park.classList.add("hidden");
  if (next) openCrack(next.stop, next.demo);
});

document.querySelector("#keep-driving").addEventListener("click", () => {
  window.speechSynthesis?.cancel();
  pending = null;
  show("trek");
});

document.querySelector("#reveal-pack").addEventListener("click", () => show("pack"));
document.querySelector("#reveal-trek").addEventListener("click", () => show("trek"));

document.querySelector("#checkin").addEventListener("click", () => tryCheckIn(false));
document.querySelector("#demo").addEventListener("click", () => tryCheckIn(true));

render();
show("trek");

function show(screen) {
  const trekVisible = screen === "trek";
  sheet.classList.toggle("hidden", !trekVisible);
  mapHost.classList.toggle("dim", !trekVisible);
  pack.classList.toggle("hidden", screen !== "pack");
  park.classList.toggle("hidden", screen !== "park");
  reveal.classList.toggle("hidden", screen !== "reveal");
  tabTrek.setAttribute("aria-pressed", String(screen === "trek" || screen === "park" || screen === "reveal"));
  tabPack.setAttribute("aria-pressed", String(screen === "pack"));
  if (screen === "trek") mapView.invalidate();
}

function render() {
  document.body.classList.toggle("driving", state.driving);
  driveBtn.setAttribute("aria-pressed", String(state.driving));
  driveBtn.textContent = state.driving ? "Driving on" : "Driving mode";
  const stop = activeStop(TREK, state.collected);
  const title = document.querySelector("#stop-name");
  const detail = document.querySelector("#stop-detail");
  const meta = document.querySelector("#stop-meta");
  const progress = document.querySelector("#progress");
  const doneCount = TREK.stops.filter((item) => state.collected[item.id]).length;
  progress.textContent = `${doneCount} of ${TREK.stops.length} stops`;
  mapView.setCollected(state.collected);

  if (!stop) {
    title.textContent = "Trek complete";
    detail.textContent = "Both cookies are in your pack. Rewards stay in the app and have no cash value.";
    meta.textContent = TREK.place;
    document.querySelector("#checkin").disabled = true;
    document.querySelector("#demo").disabled = true;
  } else {
    title.textContent = stop.name;
    detail.textContent = stop.detail;
    const where = user ? formatDistance(distanceMeters(user, stop)) : "Location not shared yet";
    const zone = user && inRange(user, stop, TREK.radiusMeters) ? "Inside the pickup zone." : `${TREK.radiusMeters} m pickup.`;
    meta.textContent = `${stop.address} · ${where} · ${zone}`;
    document.querySelector("#checkin").disabled = false;
    document.querySelector("#demo").disabled = false;
  }

  renderPack();
}

function renderPack() {
  const list = document.querySelector("#pack-list");
  const items = Object.values(state.collected);
  if (items.length === 0) {
    list.innerHTML = `<p class="empty">Crack a cookie on the trek to fill your pack.</p>`;
    return;
  }
  list.innerHTML = items
    .map((item) => {
      const color = rarityColor(item.rarity);
      return `<article class="reward-card">
        <span class="swatch" style="background:${color}"></span>
        <div>
          <p class="rarity" style="color:${color}">${rarityLabel(item.rarity)}</p>
          <h3>${escapeHtml(item.name)}</h3>
          <p>${item.kind === "keychain" ? "Keychain collectible" : "Skin collectible"}${item.demo ? " · demo check-in" : ""}</p>
        </div>
      </article>`;
    })
    .join("");
}

function tryCheckIn(demo) {
  const stop = activeStop(TREK, state.collected);
  if (!stop) return;
  if (!demo) {
    if (!user) {
      startWatch()
        .then(() => {
          if (user && inRange(user, stop, TREK.radiusMeters)) begin(stop, false);
          else toast("Not in the pickup zone yet. You can still use demo mode.");
        })
        .catch(() => toast("Location is off. Demo mode still finishes the trek."));
      return;
    }
    if (!inRange(user, stop, TREK.radiusMeters)) {
      toast("Move closer, or use demo mode.");
      return;
    }
  }
  begin(stop, demo);
}

function begin(stop, demo) {
  if (needsParkGate({ driving: state.driving, speedMps })) {
    pending = { stop, demo };
    show("park");
    speak("Park safely first.");
    return;
  }
  openCrack(stop, demo);
}

function openCrack(stop, demo) {
  runCrack({
    reward: stop.reward,
    root: document.body,
    onCracked() {
      state.collected[stop.id] = {
        ...stop.reward,
        stopId: stop.id,
        at: new Date().toISOString(),
        demo,
      };
      saveState(state);
      const card = document.querySelector("#reveal-card");
      const color = rarityColor(stop.reward.rarity);
      card.innerHTML = `
        <p class="rarity" style="color:${color}">${rarityLabel(stop.reward.rarity)}</p>
        <h2>${escapeHtml(stop.reward.name)}</h2>
        <p>In your pack. An in-app collectible with no cash value.</p>
      `;
      render();
      show("reveal");
    },
    onCancel() {
      toast("Cookie closed.");
      show("trek");
    },
  }).catch(() => {
    toast("Could not open the cookie.");
    show("trek");
  });
}

async function startWatch() {
  const perm = await Geolocation.requestPermissions().catch(() => ({ location: "granted" }));
  if (perm.location === "denied") throw new Error("denied");
  if (watchId) await Geolocation.clearWatch({ id: watchId }).catch(() => {});
  watchId = await Geolocation.watchPosition(
    { enableHighAccuracy: true, timeout: 12000 },
    (pos, err) => {
      if (err || !pos) return;
      user = { lat: pos.coords.latitude, lng: pos.coords.longitude };
      speedMps = typeof pos.coords.speed === "number" ? pos.coords.speed : null;
      mapView.setUser(user);
      render();
    },
  );
}

function speak(text) {
  if (!("speechSynthesis" in window)) return;
  window.speechSynthesis.cancel();
  const utter = new SpeechSynthesisUtterance(text);
  utter.rate = 0.96;
  window.speechSynthesis.speak(utter);
}

function toast(message) {
  toastEl.textContent = message;
  toastEl.classList.add("show");
  window.setTimeout(() => toastEl.classList.remove("show"), 2600);
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}
