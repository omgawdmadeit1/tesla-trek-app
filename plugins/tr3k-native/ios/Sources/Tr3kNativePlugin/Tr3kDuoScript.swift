import Foundation

/// Injected beside the native shim on every page, including https://tr3k.app/play/.
///
/// Wide means the bridge reported a regular horizontal size class. The page
/// then puts the Rolodex and the Start dock side by side, and during a Tr3k
/// puts the map beside the turn card. A compact size class keeps today's stack.
/// Partially open hinge updates park the pet and ask the existing coach for one line.
enum Tr3kDuoScript {
    static let source = #"""
(function () {
  var STYLE_ID = "tr3k-duo-css";
  var CSS = ""
    + "html.tr3k-wide{--tr3k-pane:min(420px,max(280px,38vw));}"
    + "html[data-tr3k-hinge='partiallyOpen'] #dockpet,html[data-tr3k-hinge='partiallyOpen'] .lg-pet{"
    + "transform:translateY(10px) rotate(-12deg);transform-origin:50% 80%;}"
    + "html.tr3k-wide body.lg.home #menu.on{margin-right:var(--tr3k-pane);width:auto;}"
    + "html.tr3k-wide body.lg.home #menu.on #list{padding-right:12px;}"
    + "html.tr3k-wide body.lg.home #menu.on .rl-wrap{max-height:none;height:calc(100dvh - 88px - env(safe-area-inset-top) - env(safe-area-inset-bottom));}"
    + "html.tr3k-wide body.lg.home .lg-dock{position:fixed;top:calc(52px + max(env(safe-area-inset-top),var(--tr3k-safe-top,0px)));right:0;bottom:0;left:auto;"
    + "width:var(--tr3k-pane);max-width:none;margin:0;justify-content:center;z-index:30;"
    + "padding-right:calc(12px + max(env(safe-area-inset-right),var(--tr3k-safe-right,0px)));"
    + "padding-bottom:calc(12px + max(env(safe-area-inset-bottom),var(--tr3k-safe-bottom,0px)));"
    + "padding-left:calc(12px + max(env(safe-area-inset-left),var(--tr3k-safe-left,0px)));}"
    + "html.tr3k-wide body.lg.home .lg-rail.r,html.tr3k-wide body.lg.home .lg-pet{"
    + "right:calc(var(--tr3k-pane) + 8px + max(env(safe-area-inset-right),var(--tr3k-safe-right,0px)));}"
    + "html.tr3k-wide body.navon #top,html.tr3k-wide body.navon #bot{left:auto;right:0;width:var(--tr3k-pane);box-sizing:border-box;}"
    + "html.tr3k-wide body.navon #nav #map{left:0;right:var(--tr3k-pane);}"
    + "html.tr3k-wide body.navon #mctl{right:calc(var(--tr3k-pane) + 12px);}"
    + "html[data-tr3k-vbar='leading'] .lg-rail.l{left:calc(8px + max(env(safe-area-inset-left),var(--tr3k-safe-left,0px)));}"
    + "html[data-tr3k-vbar='trailing'] body.lg header{padding-right:calc(12px + max(env(safe-area-inset-right),var(--tr3k-safe-right,0px)));}"
    + "html.tr3k-wide .sheet,html.tr3k-wide .gate,html.tr3k-wide .tabs{left:auto;right:max(12px,env(safe-area-inset-right));width:min(420px,42vw);}"
    + "html.tr3k-wide .sheet,html.tr3k-wide .gate{top:calc(72px + env(safe-area-inset-top));bottom:calc(72px + env(safe-area-inset-bottom));max-height:none;}"
    + "html.tr3k-wide .top{padding-left:calc(14px + env(safe-area-inset-left));padding-right:calc(14px + env(safe-area-inset-right));}";

  function installCss() {
    if (document.getElementById(STYLE_ID)) return;
    var style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = CSS;
    (document.head || document.documentElement).appendChild(style);
  }

  function columnWidth() {
    var width = window.innerWidth || document.documentElement.clientWidth || 0;
    return Math.round(Math.min(Math.max(width * 0.38, 280), 420));
  }

  function guessWide() {
    var width = window.innerWidth || 0;
    var height = window.innerHeight || 0;
    return width >= 700 && height > 0 && width >= height * 0.85;
  }

  function syncGuess() {
    if (window.__tr3kNativeSurface) return;
    var wide = guessWide();
    document.documentElement.classList.toggle("tr3k-wide", wide);
    document.documentElement.setAttribute("data-tr3k-wide", wide ? "1" : "0");
  }

  function setSafe(name, value) {
    var px = (typeof value === "number" && isFinite(value) ? value : 0) + "px";
    document.documentElement.style.setProperty(name, px);
  }

  function duoNavInsets() {
    var root = document.documentElement;
    function read(name) {
      var raw = root.style.getPropertyValue(name);
      var n = parseFloat(raw);
      return isFinite(n) ? n : 0;
    }
    return {
      top: read("--tr3k-safe-top"),
      left: read("--tr3k-safe-left"),
      bottom: 0,
      right: Math.max(columnWidth(), read("--tr3k-safe-right"))
    };
  }

  function adjustDuoLayout(opts) {
    var root = document.documentElement;
    var wide = root.getAttribute("data-tr3k-wide") === "1";
    var navigating = document.body && document.body.classList.contains("navon");
    var next = opts || {};
    if (!wide || !navigating) return next;
    var copy = {};
    Object.keys(next).forEach(function (key) { copy[key] = next[key]; });
    copy.insets = duoNavInsets();
    return copy;
  }

  function wrapNative() {
    var api = window.tr3kNative;
    if (!api || api.__duoWrapped) return;
    api.__duoWrapped = true;
    if (typeof api.setLayout === "function") {
      var setLayout = api.setLayout;
      api.setLayout = function (opts) { return setLayout.call(api, adjustDuoLayout(opts)); };
    }
    if (typeof api.showMap === "function") {
      var showMap = api.showMap;
      api.showMap = function (opts) { return showMap.call(api, adjustDuoLayout(opts)); };
    }
    api.onSurface = function (cb) {
      if (typeof cb !== "function") return null;
      function handler(event) { try { cb(event.detail || {}); } catch (e) {} }
      window.addEventListener("tr3ksurface", handler);
      return { remove: function () { window.removeEventListener("tr3ksurface", handler); } };
    };
  }

  window.__tr3kApplySurface = function (surface) {
    if (!surface) return;
    window.__tr3kNativeSurface = true;
    var root = document.documentElement;
    var wide = !!surface.wide;
    root.classList.toggle("tr3k-wide", wide);
    root.setAttribute("data-tr3k-wide", wide ? "1" : "0");
    root.setAttribute("data-tr3k-vbar", surface.vbar || "none");
    var safe = surface.safe || {};
    setSafe("--tr3k-safe-top", safe.top);
    setSafe("--tr3k-safe-left", safe.left);
    setSafe("--tr3k-safe-bottom", safe.bottom);
    setSafe("--tr3k-safe-right", safe.right);
    if (surface.hinge && surface.hinge.status) {
      root.setAttribute("data-tr3k-hinge", surface.hinge.status);
      try { window.dispatchEvent(new CustomEvent("tr3khinge", { detail: surface.hinge })); } catch (e) {}
      if (surface.coach && surface.hinge.status === "partiallyOpen") {
        try {
          window.dispatchEvent(new CustomEvent("tr3kcoach", {
            detail: { event: "park", place: "hinge" }
          }));
        } catch (e) {}
      }
    } else if (surface.hinge === null) {
      root.removeAttribute("data-tr3k-hinge");
    }
    try { window.dispatchEvent(new Event("resize")); } catch (e) {}
    try { window.dispatchEvent(new CustomEvent("tr3ksurface", { detail: surface })); } catch (e) {}
    if (document.body && document.body.classList.contains("navon") && window.tr3kNative && typeof window.tr3kNative.setLayout === "function") {
      window.tr3kNative.setLayout({});
    }
  };

  installCss();
  syncGuess();
  wrapNative();
  window.addEventListener("tr3knativeready", wrapNative);
  window.addEventListener("resize", syncGuess);
  if (window.visualViewport) window.visualViewport.addEventListener("resize", syncGuess);
})();
"""#
}
