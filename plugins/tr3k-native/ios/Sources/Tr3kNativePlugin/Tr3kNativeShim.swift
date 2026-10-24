import Foundation

/// Injected at document start into every page the shell loads (including https://tr3k.app/play).
/// Exposes window.tr3kNative and upgrades navigator.geolocation to native Core Location.
/// Map, arrival, share, haptics, and Live Activity methods (shim version 3)
/// are documented in plugins/tr3k-native/README.md.
enum Tr3kNativeShim {
    static let source = #"""
(function () {
  if (window.tr3kNative && window.tr3kNative.__native) return;
  function plugin() {
    var cap = window.Capacitor;
    if (!cap) return null;
    if (cap.Plugins && cap.Plugins.Tr3kNative) return cap.Plugins.Tr3kNative;
    if (typeof cap.registerPlugin === "function") return cap.registerPlugin("Tr3kNative");
    return null;
  }
  function call(name, args) {
    var p = plugin();
    if (!p || typeof p[name] !== "function") return Promise.reject(new Error("Tr3k native bridge is not ready"));
    return p[name](args || {});
  }
  var watchers = {};
  var nextId = 1;
  var listener = null;
  function ensureListener() {
    if (listener) return;
    var p = plugin();
    if (!p || typeof p.addListener !== "function") return;
    listener = p.addListener("location", function (pos) {
      Object.keys(watchers).forEach(function (id) { try { watchers[id].ok(pos); } catch (e) {} });
    });
    p.addListener("locationError", function (err) {
      Object.keys(watchers).forEach(function (id) { var w = watchers[id]; if (w.fail) try { w.fail(err); } catch (e) {} });
    });
  }
  function toPosition(r) {
    return {
      coords: {
        latitude: r.latitude, longitude: r.longitude, accuracy: r.accuracy,
        altitude: r.altitude, altitudeAccuracy: r.altitudeAccuracy,
        heading: r.heading, speed: r.speed
      },
      timestamp: r.timestamp
    };
  }
  function toError(e) {
    var msg = (e && e.message) || String(e);
    var code = /denied/i.test(msg) ? 1 : /timeout/i.test(msg) ? 3 : 2;
    return { code: code, message: msg, PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 };
  }
  function listen(event, cb) {
    var p = plugin();
    if (!p || typeof p.addListener !== "function") return null;
    return p.addListener(event, cb);
  }
  var api = {
    __native: true,
    platform: "ios",
    version: 3,
    getLocation: function (opts) { return call("getLocation", opts).then(toPosition); },
    watchLocation: function (onPos, onErr) {
      var id = nextId++;
      watchers[id] = { ok: function (r) { onPos(toPosition(r)); }, fail: onErr ? function (e) { onErr(toError(e)); } : null };
      ensureListener();
      call("startWatch", {}).catch(function (e) { if (onErr) onErr(toError(e)); });
      return id;
    },
    clearWatch: function (id) {
      delete watchers[id];
      if (Object.keys(watchers).length === 0) call("stopWatch", {}).catch(function () {});
    },
    requestPermissions: function (opts) { return call("requestPermissions", opts); },
    requestNotifications: function () { return call("requestNotifications", {}); },
    setStops: function (stops, opts) {
      var o = opts || {};
      return call("setStops", { stops: stops || [], radius: o.radius, title: o.title, body: o.body });
    },
    clearStops: function () { return call("clearStops", {}); },
    onArrival: function (cb) {
      var p = plugin();
      if (!p || typeof p.addListener !== "function") return null;
      return p.addListener("arrival", cb);
    },
    isARSupported: function () { return call("isARSupported", {}).then(function (r) { return !!(r && r.supported); }); },
    openAR: function (opts) { return call("openAR", opts || {}); },
    isNativeMapSupported: function () {
      var p = plugin();
      if (!p || typeof p.isNativeMapSupported !== "function") return Promise.resolve(false);
      return call("isNativeMapSupported", {}).then(function (r) { return !!(r && r.supported); }).catch(function () { return false; });
    },
    showMap: function (opts) { return call("showMap", opts || {}); },
    hideMap: function () { return call("hideMap", {}); },
    setMapType: function (type) {
      if (type && typeof type === "object") return call("setMapType", type);
      return call("setMapType", { type: type });
    },
    setCamera: function (camera) { return call("setCamera", camera || {}); },
    setFollow: function (on, opts) {
      if (on && typeof on === "object") {
        return call("setFollow", {
          follow: !!on.follow,
          followHeading: on.followHeading === true || on.heading === true
        });
      }
      var extra = opts || {};
      return call("setFollow", {
        follow: !!on,
        followHeading: extra.followHeading === true || extra.heading === true
      });
    },
    resetNorth: function () { return call("resetNorth", {}); },
    zoomIn: function () { return call("zoomIn", {}); },
    zoomOut: function () { return call("zoomOut", {}); },
    setLayout: function (opts) { return call("setLayout", opts || {}); },
    setRoute: function (route) { return call("setRoute", route || {}); },
    clearRoute: function () { return call("clearRoute", {}); },
    share: function (opts) { return call("share", opts || {}); },
    getLastDeepLink: function () { return call("getLastDeepLink", {}); },
    onDeepLink: function (cb) {
      if (typeof cb !== "function") return null;
      var saw = null;
      function emit(detail) {
        if (!detail || !detail.url) return;
        var token = detail.issuedAt || detail.url;
        if (saw === token) return;
        saw = token;
        try { cb(detail); } catch (e) {}
      }
      if (api.lastDeepLink) emit(api.lastDeepLink);
      function handler(event) { emit(event && event.detail); }
      window.addEventListener("tr3kdeepLink", handler);
      return { remove: function () { window.removeEventListener("tr3kdeepLink", handler); } };
    },
    lastDeepLink: null,
    haptic: function (kind) {
      if (kind && typeof kind === "object") return call("haptic", kind);
      return call("haptic", { kind: kind || "medium" });
    },
    startLiveActivity: function (opts) { return call("startLiveActivity", opts || {}); },
    updateLiveActivity: function (opts) { return call("updateLiveActivity", opts || {}); },
    endLiveActivity: function (opts) { return call("endLiveActivity", opts || {}); },
    onMapReady: function (cb) { return listen("mapReady", cb); },
    onFollowPaused: function (cb) { return listen("followPaused", cb); },
    onCameraChanged: function (cb) { return listen("cameraChanged", cb); },
    addMapListener: function (event, cb) { return listen(event, cb); }
  };
  function deliverDeepLink(detail) {
    if (!detail || !detail.url) return;
    if (detail.issuedAt && api._deepLinkIssuedAt === detail.issuedAt) return;
    api._deepLinkIssuedAt = detail.issuedAt || null;
    api.lastDeepLink = detail;
    try { window.dispatchEvent(new CustomEvent("tr3kdeepLink", { detail: detail })); } catch (e) {}
  }
  window.__tr3kDeliverDeepLink = deliverDeepLink;
  window.tr3kNative = api;
  call("getLastDeepLink", {}).then(function (data) { deliverDeepLink(data); }).catch(function () {});

  try {
    var geo = {
      getCurrentPosition: function (ok, fail, opts) {
        api.getLocation(opts).then(ok, function (e) { if (fail) fail(toError(e)); });
      },
      watchPosition: function (ok, fail) { return api.watchLocation(ok, fail); },
      clearWatch: function (id) { api.clearWatch(id); }
    };
    Object.defineProperty(navigator, "geolocation", { configurable: true, get: function () { return geo; } });
  } catch (e) {}

  try { window.dispatchEvent(new Event("tr3knativeready")); } catch (e) {}
})();
"""#
}
