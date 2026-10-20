import { Capacitor } from "@capacitor/core";
import { Haptics, ImpactStyle } from "@capacitor/haptics";
import { mountCrackScene } from "./crack-scene.js";
import { chooseCrackMode } from "./logic.js";
import { nativeCrackAvailable, openNativeCrack } from "./ar-native.js";

export async function runCrack({ reward, root, onCracked, onCancel }) {
  const platform = Capacitor.getPlatform() === "ios" ? "ios" : "web";
  // Start permission prompts inside the check-in tap, before any await.
  const cameraPromise = platform === "ios" ? null : requestCamera();
  const orientationPromise = platform === "ios" ? null : requestOrientation();

  if (platform === "ios" && (await nativeCrackAvailable())) {
    try {
      const result = await openNativeCrack(reward);
      if (result?.cracked) {
        onCracked({ mode: "arkit" });
        return;
      }
      if (result?.reason === "closed") {
        onCancel();
        return;
      }
    } catch {
      // The native view is missing. Fall through to the web scene.
    }
  }

  const stream = cameraPromise ? await cameraPromise : await requestCamera();
  const orientation = orientationPromise ? await orientationPromise : false;
  const mode = chooseCrackMode({
    platform: "web",
    nativeAvailable: false,
    cameraGranted: Boolean(stream),
  });
  await showWebCrack({ reward, root, stream, mode, orientation, onCracked, onCancel });
}

function requestOrientation() {
  const orientationEvent = window.DeviceOrientationEvent;
  if (!orientationEvent) return Promise.resolve(false);
  if (typeof orientationEvent.requestPermission !== "function") return Promise.resolve(true);
  return orientationEvent
    .requestPermission()
    .then((state) => state === "granted")
    .catch(() => false);
}

function requestCamera() {
  if (!navigator.mediaDevices?.getUserMedia) return Promise.resolve(null);
  return new Promise((resolve) => {
    let settled = false;
    const finish = (stream) => {
      if (settled) {
        if (stream) {
          for (const track of stream.getTracks()) track.stop();
        }
        return;
      }
      settled = true;
      resolve(stream);
    };
    const timer = setTimeout(() => finish(null), 7000);
    navigator.mediaDevices
      .getUserMedia({ audio: false, video: { facingMode: { ideal: "environment" } } })
      .then((stream) => {
        clearTimeout(timer);
        finish(stream);
      })
      .catch(() => {
        clearTimeout(timer);
        finish(null);
      });
  });
}

function mountPlainCookie(view, reward) {
  const cookie = document.createElement("button");
  cookie.type = "button";
  cookie.className = "plain-cookie";
  cookie.textContent = "Tap the cookie";
  view.appendChild(cookie);
  let cracked = false;
  let notify = () => {};
  cookie.addEventListener("click", () => {
    if (cracked) return;
    cracked = true;
    cookie.classList.add("open");
    cookie.textContent = reward.name;
    window.setTimeout(() => notify(), 600);
  });
  return {
    crack() {
      cookie.click();
      return true;
    },
    setOnCracked(fn) {
      notify = fn;
    },
    resize() {},
    destroy() {
      cookie.remove();
    },
  };
}

function showWebCrack({ reward, root, stream, mode, orientation, onCracked, onCancel }) {
  const view = document.createElement("section");
  view.className = `crack-view crack-${mode}`;
  view.innerHTML = `
    <video class="crack-video" playsinline autoplay muted></video>
    <canvas class="crack-canvas"></canvas>
    <div class="crack-hud">
      <p class="crack-kicker"></p>
      <p class="crack-hint">Tap the cookie.</p>
      <button type="button" class="btn primary crack-action">Tap the cookie</button>
      <button type="button" class="btn ghost crack-close">Close</button>
    </div>
  `;
  root.appendChild(view);
  const video = view.querySelector("video");
  const canvas = view.querySelector("canvas");
  const hint = view.querySelector(".crack-hint");
  const kicker = view.querySelector(".crack-kicker");
  const action = view.querySelector(".crack-action");
  const close = view.querySelector(".crack-close");

  if (mode === "camera" && stream) {
    video.srcObject = stream;
    video.play().catch(() => {});
    kicker.textContent = orientation
      ? "Camera view. The cookie stays where it was placed. Look around, then tap it."
      : "Camera view. The cookie sits in front of the lens.";
  } else {
    kicker.textContent = "Camera is off, so the cookie opens on a plain stage.";
    hint.textContent = "Same crack, without the street behind it.";
  }

  let scene;
  try {
    scene = mountCrackScene(canvas, {
      reward,
      transparent: mode === "camera",
      orientation: mode === "camera" && orientation,
    });
  } catch {
    scene = mountPlainCookie(view, reward);
    kicker.textContent = "This phone is using the plain cookie.";
  }
  let finished = false;
  scene.setOnCracked(() => {
    finished = true;
    hint.textContent = `${reward.name} is out. It spins in front of you.`;
    action.textContent = "Keep it";
    pulse();
  });

  const onAction = () => {
    if (!finished) {
      if (scene.crack()) {
        hint.textContent = "Shell's opening.";
        pulse();
      }
      return;
    }
    cleanup();
    onCracked({ mode });
  };
  const onClose = () => {
    cleanup();
    onCancel();
  };
  action.addEventListener("click", onAction);
  close.addEventListener("click", onClose);
  const onResize = () => scene.resize();
  window.addEventListener("resize", onResize);

  function cleanup() {
    window.removeEventListener("resize", onResize);
    scene.destroy();
    if (stream) {
      for (const track of stream.getTracks()) track.stop();
    }
    view.remove();
  }
}

function pulse() {
  Haptics.impact({ style: ImpactStyle.Medium }).catch(() => {});
}
