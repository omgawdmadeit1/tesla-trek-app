import ARKit
import AVFoundation
import Capacitor
import CoreLocation
import Tr3kActivityKit
import Tr3kAppGroup
import UIKit
import UserNotifications
import WebKit
import WidgetKit

@objc(Tr3kNativePlugin)
public class Tr3kNativePlugin: CAPPlugin, CAPBridgedPlugin, CLLocationManagerDelegate {
    public let identifier = "Tr3kNativePlugin"
    public let jsName = "Tr3kNative"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getLocation", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startWatch", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopWatch", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestNotifications", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setStops", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clearStops", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setLiveDrop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setLiveDrops", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getLiveDrop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getLiveDrops", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clearLiveDrops", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openXLiveDrop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "previewLiveDrop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getLastLiveDrop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setLiveDropSurface", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "share", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getLastDeepLink", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "haptic", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "speak", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopSpeaking", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startLiveActivity", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "updateLiveActivity", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "endLiveActivity", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isARSupported", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openAR", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isNativeMapSupported", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "showMap", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "hideMap", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setMapType", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setCamera", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setFollow", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "resetNorth", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "zoomIn", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "zoomOut", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setLayout", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setRoute", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clearRoute", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveOfflineTreks", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getOfflineTreks", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clearOfflineTreks", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "signInWithApple", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getAppleSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "signOutApple", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openSettings", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "arStatus", returnType: CAPPluginReturnPromise)
    ]

    private var manager: CLLocationManager!
    private var pendingFixes: [CAPPluginCall] = []
    private var pendingAuth: [CAPPluginCall] = []
    private var watching = false
    private var mapController: Tr3kNativeMapController?
    private var upgradeAlwaysAfterWhenInUse = false
    private var didPromptAlways = false
    private var pendingAlwaysUpgrade = false
    private var lastDeepLink: [String: Any]?
    private var deepLinkSerial: Double = 0
    private var lastDeliveredURL: String?
    private var lastDeliveredAt: TimeInterval = 0
    private var appleSignIn: Tr3kAppleSignIn?
    private var webPresentsLiveDrop = false
    private var liveDropSurfaceMark: Double = 0
    private var sheetWork: DispatchWorkItem?
    private var pendingSheetDrop: Tr3kLiveDrop?
    private var lastLiveDrop: [String: Any]?
    private var lastLiveDropAt: [String: TimeInterval] = [:]
    /// True while the native map is up and GPS should continue with the screen locked.
    private var keepBackgroundLocation = false

    override public func load() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenURL(_:)),
            name: .capacitorOpenURL,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenURL(_:)),
            name: .capacitorOpenUniversalLink,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        Tr3kSpeech.shared.onEvent = { [weak self] name, data in
            guard let self else { return }
            self.notifyListeners(name, data: data)
            guard name == "speechFinish" else { return }
            DispatchQueue.main.async {
                // The arrival line is spoken after the map is dismissed. Release
                // the session when that line ends so music and GPS return to normal.
                guard self.mapController?.isMapVisible != true else { return }
                guard !Tr3kSpeech.shared.isSpeaking else { return }
                guard Tr3kSpeech.shared.sessionArmed else { return }
                Tr3kSpeech.shared.disarmSession()
                self.syncBackgroundNavigation()
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        Tr3kArrivalMonitor.prepareForRelaunch()
        Tr3kArrivalMonitor.shared.onArrival = { [weak self] stopId in
            guard let self else { return }
            self.notifyListeners("arrival", data: ["stopId": stopId], retainUntilConsumed: true)
            self.unlockArrivedStop(stopId)
            if #available(iOS 16.2, *) {
                Task { @MainActor in
                    Tr3kLiveActivityMirror.shared.noteArrival(stopId)
                }
            }
        }
        DispatchQueue.main.async {
            self.ensureLocationManager()
            if self.pendingAlwaysUpgrade {
                self.pendingAlwaysUpgrade = false
                self.ensureAlwaysAuthorization()
            }
            self.injectShim()
        }
    }

    // MARK: JS shim

    private func injectShim() {
        guard let webView = bridge?.webView else { return }
        let script = WKUserScript(source: Tr3kNativeShim.source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)
        // Cover a page that already started loading before the plugin was ready.
        webView.evaluateJavaScript(Tr3kNativeShim.source) { [weak self] _, _ in
            guard let self, let lastDeepLink = self.lastDeepLink else { return }
            self.emitDeepLink(lastDeepLink)
        }
    }

    /// Re-arm spoken audio while Tr3k is still allowed to activate a session.
    /// The screen lock happens immediately after this.
    @objc private func appWillResignActive() {
        guard navigationSessionActive() else { return }
        if Tr3kSpeech.shared.sessionArmed {
            Tr3kSpeech.shared.armSession()
        }
        syncBackgroundNavigation()
    }

    /// Region alerts keep working in the background. Continuous GPS stays on
    /// only during navigation, so the page can speak the next direction.
    @objc private func appDidEnterBackground() {
        guard manager != nil else { return }
        if navigationSessionActive() {
            syncBackgroundNavigation()
            guard isAuthorized(authStatus()) else { return }
            if watching || mapController?.wantsFollow == true {
                manager.startUpdatingLocation()
            }
            if mapController?.wantsFollowHeading == true {
                applyHeadingOrientation()
                manager.headingFilter = 5
                manager.startUpdatingHeading()
            }
            return
        }
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    @objc private func appDidBecomeActive() {
        guard let drop = pendingSheetDrop else { return }
        pendingSheetDrop = nil
        guard !webPresentsLiveDrop else { return }
        presentLiveDropSheet(drop)
        Tr3kHaptics.play("strong")
    }

    @objc private func appWillEnterForeground() {
        guard manager != nil else { return }
        guard isAuthorized(authStatus()) else { return }
        if watching || !pendingFixes.isEmpty || mapController?.wantsFollow == true {
            manager.startUpdatingLocation()
        }
        if mapController?.wantsFollowHeading == true {
            applyHeadingOrientation()
            manager.headingFilter = 5
            manager.startUpdatingHeading()
        }
    }

    // MARK: Location

    private func authStatus() -> CLAuthorizationStatus {
        manager.authorizationStatus
    }

    private func statusName(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: return "always"
        case .authorizedWhenInUse: return "whenInUse"
        case .denied: return "denied"
        case .restricted: return "restricted"
        default: return "prompt"
        }
    }

    private func isAuthorized(_ s: CLAuthorizationStatus) -> Bool {
        s == .authorizedAlways || s == .authorizedWhenInUse
    }

    private func fixPayload(_ loc: CLLocation) -> [String: Any] {
        [
            "latitude": loc.coordinate.latitude,
            "longitude": loc.coordinate.longitude,
            "accuracy": loc.horizontalAccuracy,
            "altitude": loc.verticalAccuracy >= 0 ? loc.altitude : NSNull(),
            "altitudeAccuracy": loc.verticalAccuracy >= 0 ? loc.verticalAccuracy : NSNull(),
            "heading": loc.course >= 0 ? loc.course : NSNull(),
            "speed": loc.speed >= 0 ? loc.speed : NSNull(),
            "timestamp": loc.timestamp.timeIntervalSince1970 * 1000
        ]
    }

    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.ensureLocationManager()
            let always = call.getBool("always") ?? false
            let status = self.authStatus()
            if status == .notDetermined {
                self.pendingAuth.append(call)
                if always { self.upgradeAlwaysAfterWhenInUse = true }
                self.manager.requestWhenInUseAuthorization()
            } else if always && status == .authorizedWhenInUse {
                // Resolve now. Choosing "Keep Only While Using" does not change
                // the status, so the delegate may not run again.
                self.didPromptAlways = true
                self.manager.requestAlwaysAuthorization()
                call.resolve(self.authPayload(alwaysPrompted: true))
            } else {
                call.resolve(self.authPayload(alwaysPrompted: false))
            }
        }
    }

    private func authPayload(alwaysPrompted: Bool) -> [String: Any] {
        let status = authStatus()
        return [
            "location": statusName(status),
            "alwaysPrompted": alwaysPrompted,
            "backgroundAlerts": status == .authorizedAlways
        ]
    }

    /// When In Use first, then Always. A denied Always upgrade leaves When In Use in place.
    private func ensureAlwaysAuthorization() {
        guard manager != nil else {
            pendingAlwaysUpgrade = true
            return
        }
        switch authStatus() {
        case .notDetermined:
            upgradeAlwaysAfterWhenInUse = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            guard !didPromptAlways else { return }
            didPromptAlways = true
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    private func ensureLocationManager() {
        if manager != nil { return }
        manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
    }

    private func resolvePendingAuth(alwaysPrompted: Bool) {
        let calls = pendingAuth
        pendingAuth.removeAll()
        let payload = authPayload(alwaysPrompted: alwaysPrompted)
        calls.forEach { $0.resolve(payload) }
    }

    @objc func getLocation(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let status = self.authStatus()
            if status == .denied || status == .restricted {
                call.reject("Location permission denied")
                return
            }
            let maxAge = (call.getDouble("maximumAge") ?? 0) / 1000
            if maxAge > 0, let last = self.manager.location, -last.timestamp.timeIntervalSinceNow <= maxAge {
                call.resolve(self.fixPayload(last))
                return
            }
            call.keepAlive = true
            self.pendingFixes.append(call)
            let timeout = (call.getDouble("timeout") ?? 15000) / 1000
            DispatchQueue.main.asyncAfter(deadline: .now() + max(1, timeout)) {
                if let idx = self.pendingFixes.firstIndex(where: { $0.callbackId == call.callbackId }) {
                    self.pendingFixes.remove(at: idx)
                    call.reject("Location timeout")
                    self.bridge?.releaseCall(call)
                }
            }
            if status == .notDetermined {
                self.manager.requestWhenInUseAuthorization()
            } else {
                self.manager.startUpdatingLocation()
            }
        }
    }

    @objc func startWatch(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.watching = true
            if self.authStatus() == .notDetermined {
                self.manager.requestWhenInUseAuthorization()
            } else {
                self.manager.startUpdatingLocation()
            }
            call.resolve()
        }
    }

    @objc func stopWatch(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.watching = false
            if self.pendingFixes.isEmpty && self.mapController?.wantsFollow != true && !self.keepBackgroundLocation {
                self.manager.stopUpdatingLocation()
            }
            call.resolve()
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse && upgradeAlwaysAfterWhenInUse {
            upgradeAlwaysAfterWhenInUse = false
            didPromptAlways = true
            resolvePendingAuth(alwaysPrompted: true)
            manager.requestAlwaysAuthorization()
        } else if status != .notDetermined {
            upgradeAlwaysAfterWhenInUse = false
            resolvePendingAuth(alwaysPrompted: false)
        }
        if isAuthorized(status) {
            self.syncBackgroundNavigation()
            if watching || !pendingFixes.isEmpty || mapController?.wantsFollow == true {
                manager.startUpdatingLocation()
            }
            if mapController?.wantsFollowHeading == true {
                applyHeadingOrientation()
                manager.headingFilter = 5
                manager.startUpdatingHeading()
            }
        } else if status == .denied || status == .restricted {
            let calls = pendingFixes
            pendingFixes.removeAll()
            calls.forEach { $0.reject("Location permission denied"); bridge?.releaseCall($0) }
            notifyListeners("locationError", data: ["message": "Location permission denied"])
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        let payload = fixPayload(loc)
        if !pendingFixes.isEmpty {
            let calls = pendingFixes
            pendingFixes.removeAll()
            calls.forEach { $0.resolve(payload); bridge?.releaseCall($0) }
        }
        if watching {
            notifyListeners("location", data: payload)
        }
        mapController?.ingest(location: loc)
        if #available(iOS 16.2, *) {
            let lat = loc.coordinate.latitude
            let lng = loc.coordinate.longitude
            let speed = loc.speed
            Task { @MainActor in
                Tr3kLiveActivityMirror.shared.noteLocation(lat: lat, lng: lng, speed: speed)
            }
        }
        if !watching && pendingFixes.isEmpty && mapController?.wantsFollow != true && !keepBackgroundLocation {
            manager.stopUpdatingLocation()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        mapController?.ingest(heading: heading)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clErr = error as? CLError {
            switch clErr.code {
            case .locationUnknown, .headingFailure:
                return
            default:
                break
            }
        }
        notifyListeners("locationError", data: ["message": error.localizedDescription])
    }

    // MARK: Stop arrival alerts (region monitoring)

    @objc func requestNotifications(_ call: CAPPluginCall) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            call.resolve(["granted": granted])
        }
    }

    @objc func setStops(_ call: CAPPluginCall) {
        let stops = call.getArray("stops", JSObject.self) ?? []
        let radius = call.getDouble("radius") ?? 75
        let title = call.getString("title")
        let body = call.getString("body")
        DispatchQueue.main.async {
            self.ensureLocationManager()
            self.ensureAlwaysAuthorization()
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            self.ingestStopDrops(stops)
            if #available(iOS 16.2, *) {
                let rows = stops.map { $0 as Any }
                Task { @MainActor in
                    Tr3kLiveActivityMirror.shared.noteStops(rows)
                }
            }
            var result = Tr3kArrivalMonitor.shared.replaceStops(stops, radius: radius, title: title, body: body)
            let status = self.authStatus()
            result["location"] = self.statusName(status)
            result["backgroundAlerts"] = status == .authorizedAlways
            call.resolve(result)
        }
    }

    @objc func clearStops(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            Tr3kArrivalMonitor.shared.clear()
            call.resolve()
        }
    }

    // MARK: X Live Drop

    @objc func setLiveDrop(_ call: CAPPluginCall) {
        let raw = call.jsObjectRepresentation
        DispatchQueue.main.async {
            guard let drop = Tr3kLiveDropStore.shared.save(raw) else {
                call.resolve(["saved": false, "reason": "invalid"])
                return
            }
            call.resolve(["saved": true, "stopId": drop.stopId, "type": drop.type])
        }
    }

    @objc func setLiveDrops(_ call: CAPPluginCall) {
        let drops = call.getArray("drops", JSObject.self) ?? []
        let replace = call.getBool("replace") ?? true
        DispatchQueue.main.async {
            let saved = Tr3kLiveDropStore.shared.replace(drops, replaceAll: replace)
            call.resolve([
                "saved": saved.count,
                "drops": saved.map { $0.queryFields() }
            ])
        }
    }

    @objc func getLiveDrop(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let id = Tr3kLiveDropStore.cleanStopId(call.getString("stopId")),
                  let drop = Tr3kLiveDropStore.shared.drop(for: id) else {
                call.resolve(["found": false])
                return
            }
            call.resolve(drop.queryFields())
        }
    }

    @objc func getLiveDrops(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            call.resolve(["drops": Tr3kLiveDropStore.shared.all().map { $0.queryFields() }])
        }
    }

    @objc func clearLiveDrops(_ call: CAPPluginCall) {
        let stopId = call.getString("stopId")
        DispatchQueue.main.async {
            let cleared = Tr3kLiveDropStore.shared.clear(stopId: stopId)
            var payload: [String: Any] = ["cleared": cleared]
            if let stopId { payload["stopId"] = stopId }
            call.resolve(payload)
        }
    }

    @objc func openXLiveDrop(_ call: CAPPluginCall) {
        let raw = call.getString("url") ?? call.getString("deepLink") ?? ""
        openLiveDropURL(raw, call: call, fallback: nil)
    }

    @objc func previewLiveDrop(_ call: CAPPluginCall) {
        let raw = call.jsObjectRepresentation
        DispatchQueue.main.async {
            let provided = ((raw["url"] as? String) ?? (raw["deepLink"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !provided.isEmpty {
                guard let drop = Tr3kLiveDropStore.parse(raw, allowMissingURL: false) else {
                    call.resolve(["shown": false, "reason": "invalid"])
                    return
                }
                if drop.stopId != "demo" {
                    _ = Tr3kLiveDropStore.shared.save(drop.storedFields())
                }
                self.emitLiveDrop(drop, source: "preview")
                call.resolve(["shown": true, "stopId": drop.stopId, "type": drop.type, "demo": drop.demo])
                return
            }
            if let id = Tr3kLiveDropStore.cleanStopId(call.getString("stopId") ?? (raw["stopId"] as? String)),
               let stored = Tr3kLiveDropStore.shared.drop(for: id) {
                self.emitLiveDrop(stored, source: "preview")
                call.resolve(["shown": true, "stopId": stored.stopId, "type": stored.type, "demo": stored.demo])
                return
            }
            if Tr3kLiveDropStore.cleanStopId(raw["stopId"]) == nil,
               let stored = Tr3kLiveDropStore.shared.all().first {
                self.emitLiveDrop(stored, source: "preview")
                call.resolve(["shown": true, "stopId": stored.stopId, "type": stored.type, "demo": stored.demo])
                return
            }
            guard let demo = Tr3kLiveDropStore.parse(["stopId": "demo", "type": "space"], allowMissingURL: true) else {
                call.resolve(["shown": false, "reason": "invalid"])
                return
            }
            self.emitLiveDrop(demo, source: "preview")
            call.resolve(["shown": true, "stopId": demo.stopId, "type": demo.type, "demo": true])
        }
    }

    @objc func getLastLiveDrop(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if let last = self.lastLiveDrop {
                call.resolve(last)
            } else {
                call.resolve(["found": false])
            }
        }
    }

    @objc func setLiveDropSurface(_ call: CAPPluginCall) {
        let owner = call.getString("owner") == "web" ? "web" : "native"
        let gen = call.getDouble("gen") ?? 0
        DispatchQueue.main.async {
            let claimed: Bool
            if owner == "web" {
                claimed = gen == 0 || gen >= self.liveDropSurfaceMark
            } else {
                // Same-generation native reset must not clobber a web claim
                // that was already applied for this page load.
                claimed = gen == 0 || gen > self.liveDropSurfaceMark
            }
            if claimed {
                if gen > self.liveDropSurfaceMark { self.liveDropSurfaceMark = gen }
                self.webPresentsLiveDrop = owner == "web"
                if self.webPresentsLiveDrop {
                    self.sheetWork?.cancel()
                    self.sheetWork = nil
                    self.pendingSheetDrop = nil
                    Tr3kLiveDropSheet.dismissIfNeeded()
                }
            }
            call.resolve(["owner": self.webPresentsLiveDrop ? "web" : "native"])
        }
    }

    private func ingestStopDrops(_ stops: [JSObject]) {
        for stop in stops {
            guard var fields = Tr3kLiveDropStore.dictionary(stop["liveDrop"]) else { continue }
            if fields["stopId"] == nil {
                fields["stopId"] = stop["id"] ?? ""
            }
            _ = Tr3kLiveDropStore.shared.save(fields)
        }
    }

    private func unlockArrivedStop(_ stopId: String) {
        guard let drop = Tr3kLiveDropStore.shared.drop(for: stopId) else { return }
        emitLiveDrop(drop, source: "arrival")
    }

    private func emitLiveDrop(_ drop: Tr3kLiveDrop, source: String) {
        let send = { self.emitLiveDropOnMain(drop, source: source) }
        if Thread.isMainThread {
            send()
        } else {
            DispatchQueue.main.async(execute: send)
        }
    }

    private func emitLiveDropOnMain(_ drop: Tr3kLiveDrop, source: String) {
        if source == "arrival" {
            let now = Date().timeIntervalSince1970
            if let last = lastLiveDropAt[drop.stopId], now - last < 30 { return }
            lastLiveDropAt[drop.stopId] = now
        }
        Tr3kHaptics.play("strong")
        let payload = drop.eventFields(
            source: source,
            unlockId: UUID().uuidString,
            issuedAt: Date().timeIntervalSince1970 * 1000
        )
        lastLiveDrop = payload
        notifyListeners("liveDropUnlock", data: payload, retainUntilConsumed: true)
        if #available(iOS 16.2, *) {
            let stopId = drop.stopId
            Task { @MainActor in
                Tr3kLiveActivityMirror.shared.noteLiveDrop(stopId: stopId)
            }
        }
        scheduleLiveDropSheet(drop)
    }

    private func scheduleLiveDropSheet(_ drop: Tr3kLiveDrop) {
        guard !webPresentsLiveDrop else { return }
        sheetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.webPresentsLiveDrop else { return }
            if UIApplication.shared.applicationState == .background {
                self.pendingSheetDrop = drop
                return
            }
            self.presentLiveDropSheet(drop)
        }
        sheetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func presentLiveDropSheet(_ drop: Tr3kLiveDrop, attempt: Int = 0) {
        guard !webPresentsLiveDrop else { return }
        guard let presenter = topPresenter() else {
            if attempt < 8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.presentLiveDropSheet(drop, attempt: attempt + 1)
                }
            } else {
                pendingSheetDrop = drop
            }
            return
        }
        if let existing = presenter as? Tr3kLiveDropSheet {
            existing.render(drop)
            return
        }
        Tr3kLiveDropSheet.present(drop: drop, from: presenter) { [weak self] url in
            self?.openLiveDropURL(url, call: nil, fallback: drop)
        }
    }

    private func openLiveDropURL(_ raw: String, call: CAPPluginCall?, fallback: Tr3kLiveDrop?) {
        Tr3kXLink.open(raw) { [weak self] result in
            if let call {
                var payload: [String: Any] = ["opened": result.opened]
                if result.opened, let url = result.url {
                    payload["url"] = url
                    if let via = result.via { payload["via"] = via }
                } else {
                    payload["reason"] = result.reason ?? "unavailable"
                }
                call.resolve(payload)
            }
            if !result.opened, let fallback, let self, !self.webPresentsLiveDrop {
                self.presentLiveDropSheet(fallback)
            }
        }
    }

    // MARK: Share sheet and deep links

    @objc func share(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let presenter = self.topPresenter() else {
                call.reject("The app view is not ready.")
                return
            }
            Tr3kShareSheet.present(
                title: call.getString("title"),
                text: call.getString("text"),
                urlString: call.getString("url"),
                from: presenter
            ) { completed in
                call.resolve(["completed": completed])
            }
        }
    }

    @objc func getLastDeepLink(_ call: CAPPluginCall) {
        if let lastDeepLink {
            call.resolve(lastDeepLink)
        } else {
            call.resolve([:])
        }
    }

    @objc private func handleOpenURL(_ notification: Notification) {
        guard let url = Tr3kDeepLink.url(from: notification) else { return }
        let key = url.absoluteString
        let now = Date().timeIntervalSince1970
        if key == lastDeliveredURL && now - lastDeliveredAt < 1.5 { return }
        guard let payload = Tr3kDeepLink.payload(for: url, issuedAt: nextIssuedAt()) else { return }
        lastDeliveredURL = key
        lastDeliveredAt = now
        lastDeepLink = payload
        notifyListeners("deepLink", data: payload, retainUntilConsumed: true)
        emitDeepLink(payload)
        if let drop = Tr3kLiveDropLink.drop(from: url) {
            emitLiveDrop(drop, source: "preview")
        }
    }

    private func nextIssuedAt() -> Double {
        deepLinkSerial += 1
        return Date().timeIntervalSince1970 * 1000 + deepLinkSerial
    }

    private func emitDeepLink(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let script = "window.__tr3kDeliverDeepLink && window.__tr3kDeliverDeepLink(\(json))"
        DispatchQueue.main.async {
            self.bridge?.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private func topPresenter() -> UIViewController? {
        var current = bridge?.viewController
        while let presented = current?.presentedViewController {
            current = presented
        }
        return current
    }

    // MARK: Haptics and Live Activity

    @objc func haptic(_ call: CAPPluginCall) {
        let kind = call.getString("kind") ?? call.getString("type") ?? "medium"
        DispatchQueue.main.async {
            let played = Tr3kHaptics.play(kind)
            call.resolve(["played": played, "kind": kind])
        }
    }

    // MARK: Spoken directions

    @objc func speak(_ call: CAPPluginCall) {
        let prompt = speechPrompt(from: call)
        DispatchQueue.main.async {
            let result = Tr3kSpeech.shared.speak(prompt)
            self.syncBackgroundNavigation()
            if #available(iOS 16.2, *), !prompt.muted {
                let line = prompt.text
                Task { @MainActor in
                    Tr3kLiveActivityMirror.shared.noteSpeech(line)
                }
            }
            call.resolve(result)
        }
    }

    @objc func stopSpeaking(_ call: CAPPluginCall) {
        let word = call.getString("boundary") == "word" || call.getString("at") == "word"
        DispatchQueue.main.async {
            let result = Tr3kSpeech.shared.stop(immediate: !word)
            self.syncBackgroundNavigation()
            call.resolve(result)
        }
    }

    private func speechPrompt(from call: CAPPluginCall) -> Tr3kSpeech.Prompt {
        let muted = call.getBool("mute") == true || call.getBool("muted") == true
        let avScale = call.getString("rateUnit") == "av" || call.getString("rateScale") == "av"
        let rawRate = Float(call.getDouble("rate") ?? (avScale ? Double(AVSpeechUtteranceDefaultSpeechRate) : 1.05))
        let rate = avScale ? rawRate : AVSpeechUtteranceDefaultSpeechRate * rawRate
        return Tr3kSpeech.Prompt(
            id: call.getString("id") ?? UUID().uuidString,
            text: call.getString("text") ?? call.getString("utterance") ?? call.getString("message") ?? "",
            rate: rate,
            pitch: Float(call.getDouble("pitch") ?? 1),
            volume: Float(call.getDouble("volume") ?? 1),
            language: call.getString("lang") ?? call.getString("language") ?? call.getString("locale") ?? "en-US",
            voice: call.getString("voice") ?? call.getString("voiceId"),
            interrupt: call.getBool("interrupt") ?? false,
            muted: muted
        )
    }

    @objc func startLiveActivity(_ call: CAPPluginCall) {
        let fields = call.jsObjectRepresentation
        guard #available(iOS 16.2, *) else {
            call.resolve(["started": false, "reason": "unsupported"])
            return
        }
        Task { @MainActor in
            let result = await Tr3kLiveActivityMirror.shared.start(fields)
            call.resolve(result)
        }
    }

    @objc func updateLiveActivity(_ call: CAPPluginCall) {
        let fields = call.jsObjectRepresentation
        guard #available(iOS 16.2, *) else {
            call.resolve(["updated": false, "reason": "unsupported"])
            return
        }
        Task { @MainActor in
            let result = await Tr3kLiveActivityMirror.shared.update(fields)
            call.resolve(result)
        }
    }

    @objc func endLiveActivity(_ call: CAPPluginCall) {
        let dismissal = call.getString("dismissal")
        guard #available(iOS 16.2, *) else {
            call.resolve(["ended": false, "reason": "unsupported"])
            return
        }
        Task { @MainActor in
            let result = await Tr3kLiveActivityMirror.shared.end(dismissal: dismissal)
            call.resolve(result)
        }
    }

    // MARK: AR pumpkin box

    @objc func isARSupported(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            call.resolve(["supported": ARWorldTrackingConfiguration.isSupported])
        }
    }

    @objc func arStatus(_ call: CAPPluginCall) {
        Tr3kARAccess.check(subject: "glowing pumpkin", prompt: false) { payload in
            call.resolve(Tr3kARAccess.fields(payload))
        }
    }

    @objc func openSettings(_ call: CAPPluginCall) {
        Tr3kARAccess.openSettings(call)
    }

    @objc func openAR(_ call: CAPPluginCall) {
        let tier = call.getString("tier") ?? "common"
        let prize = call.getString("prize") ?? ""
        DispatchQueue.main.async {
            if #available(iOS 16.2, *) {
                let rare = tier == "rare" || tier == "epic" || tier == "legendary"
                Task { @MainActor in
                    Tr3kLiveActivityMirror.shared.noteHunt(rare: rare)
                }
            }
            guard let presenter = self.bridge?.viewController else {
                call.resolve([
                    "opened": false,
                    "reason": "not_ready",
                    "tier": tier,
                    "prize": prize,
                    "supported": ARWorldTrackingConfiguration.isSupported,
                    "camera": "unavailable",
                    "canOpenSettings": false
                ])
                return
            }
            Tr3kARAccess.check(subject: "glowing pumpkin", prompt: true) { decision in
                let proceed = decision["proceed"] as? Bool ?? false
                guard proceed else {
                    var payload = Tr3kARAccess.fields(decision)
                    payload["opened"] = false
                    payload["tier"] = tier
                    payload["prize"] = prize
                    call.resolve(payload)
                    return
                }
                let view = Tr3kPumpkinARViewController()
                view.modalPresentationStyle = .fullScreen
                view.tier = tier
                view.prize = prize
                view.onFinish = { [weak presenter] opened, reason in
                    var payload = Tr3kARAccess.fields(decision)
                    payload["opened"] = opened
                    payload["reason"] = reason
                    payload["tier"] = tier
                    payload["prize"] = prize
                    let done = { call.resolve(payload) }
                    if let presenter { presenter.dismiss(animated: true, completion: done) } else { done() }
                }
                presenter.present(view, animated: true)
            }
        }
    }

    // MARK: Native MapKit map

    @objc func isNativeMapSupported(_ call: CAPPluginCall) {
        call.resolve(["supported": true])
    }

    @objc func showMap(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let webView = self.bridge?.webView, let parent = webView.superview else {
                call.reject("The app view is not ready.")
                return
            }
            if self.manager != nil, self.authStatus() == .notDetermined {
                self.manager.requestWhenInUseAuthorization()
            }
            let options = call.jsObjectRepresentation
            let snapshot = self.mapOnMain().show(in: parent, above: webView, options: options)
            self.syncBackgroundNavigation()
            self.armSpeechIfVoiceOn()
            if #available(iOS 16.2, *) {
                Task { @MainActor in
                    Tr3kLiveActivityMirror.shared.noteMap(visible: true, fields: options)
                }
            }
            call.resolve(snapshot)
        }
    }

    @objc func hideMap(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let map = self.mapController else {
                call.resolve(["visible": false])
                return
            }
            let snapshot = map.hide()
            Tr3kSpeech.shared.disarmSession()
            self.syncBackgroundNavigation()
            if #available(iOS 16.2, *) {
                Task { @MainActor in
                    Tr3kLiveActivityMirror.shared.noteMap(visible: false, fields: [:])
                }
            }
            call.resolve(snapshot)
        }
    }

    @objc func setMapType(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let raw = call.getString("type") ?? call.getString("mapType")
            call.resolve(self.mapOnMain().setMapType(raw))
        }
    }

    @objc func setCamera(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            call.resolve(self.mapOnMain().setCamera(options: call.jsObjectRepresentation))
        }
    }

    @objc func setFollow(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            call.resolve(self.mapOnMain().setFollow(options: call.jsObjectRepresentation))
        }
    }

    @objc func resetNorth(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            call.resolve(self.mapOnMain().resetNorth())
        }
    }

    @objc func zoomIn(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            call.resolve(self.mapOnMain().zoom(by: 1))
        }
    }

    @objc func zoomOut(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            call.resolve(self.mapOnMain().zoom(by: -1))
        }
    }

    @objc func setLayout(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            call.resolve(self.mapOnMain().setLayout(options: call.jsObjectRepresentation))
        }
    }

    @objc func setRoute(_ call: CAPPluginCall) {
        let options = call.jsObjectRepresentation
        DispatchQueue.main.async {
            if #available(iOS 16.2, *) {
                Task { @MainActor in
                    Tr3kLiveActivityMirror.shared.noteRoute(options)
                }
            }
            call.resolve(self.mapOnMain().setRoute(options: options))
        }
    }

    @objc func clearRoute(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            call.resolve(self.mapOnMain().clearRoute())
        }
    }

    private func mapOnMain() -> Tr3kNativeMapController {
        if let existing = mapController { return existing }
        let controller = Tr3kNativeMapController()
        controller.onEvent = { [weak self] name, data, retain in
            self?.notifyListeners(name, data: data, retainUntilConsumed: retain)
        }
        controller.onFollowNeedsLocation = { [weak self] follow, heading in
            self?.syncMapLocationDemand(follow: follow, heading: heading)
        }
        controller.fallbackCoordinate = { [weak self] in
            self?.manager?.location?.coordinate
        }
        mapController = controller
        return controller
    }

    private func syncMapLocationDemand(follow: Bool, heading: Bool) {
        guard let manager else { return }
        if follow {
            applyHeadingOrientation()
            if authStatus() == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else if isAuthorized(authStatus()) {
                manager.startUpdatingLocation()
                if heading {
                    manager.headingFilter = 5
                    manager.startUpdatingHeading()
                } else {
                    manager.stopUpdatingHeading()
                }
            }
        } else {
            manager.stopUpdatingHeading()
            if !watching && pendingFixes.isEmpty && !keepBackgroundLocation {
                manager.stopUpdatingLocation()
            }
        }
    }

    /// The native map is the navigation session. A leftover voice line after
    /// the map closes does not keep the GPS radio on.
    private func navigationSessionActive() -> Bool {
        mapController?.isMapVisible == true
    }

    /// Keep GPS running across the lock only while a trek is on screen.
    /// `allowsBackgroundLocationUpdates` throws without the location background mode.
    private func syncBackgroundNavigation() {
        guard let manager else { return }
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        let allow = navigationSessionActive() && modes?.contains("location") == true && isAuthorized(authStatus())
        keepBackgroundLocation = allow
        if allow {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.activityType = .automotiveNavigation
        } else {
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            manager.pausesLocationUpdatesAutomatically = true
            manager.activityType = .fitness
        }
    }

    /// The page stores mute in `tr3k_voice_mute`. Arm immediately so a lock in the
    /// next moment still has a playback session, then release it if voice is muted.
    private func armSpeechIfVoiceOn() {
        Tr3kSpeech.shared.armSession()
        guard let webView = bridge?.webView else { return }
        webView.evaluateJavaScript(
            "(() => { try { return localStorage.getItem('tr3k_voice_mute') } catch (e) { return null } })()"
        ) { [weak self] result, _ in
            let muted = (result as? String) == "1"
            DispatchQueue.main.async {
                guard let self, self.mapController?.isMapVisible == true else { return }
                if muted {
                    Tr3kSpeech.shared.disarmSession()
                } else {
                    Tr3kSpeech.shared.armSession()
                }
                self.syncBackgroundNavigation()
            }
        }
    }

    private func applyHeadingOrientation() {
        guard let manager else { return }
        guard let orientation = bridge?.viewController?.view.window?.windowScene?.interfaceOrientation else {
            manager.headingOrientation = .portrait
            return
        }
        switch orientation {
        case .landscapeLeft:
            manager.headingOrientation = .landscapeLeft
        case .landscapeRight:
            manager.headingOrientation = .landscapeRight
        case .portraitUpsideDown:
            manager.headingOrientation = .portraitUpsideDown
        case .portrait, .unknown:
            manager.headingOrientation = .portrait
        @unknown default:
            manager.headingOrientation = .portrait
        }
    }

    // MARK: Offline cache (App Group, slim refs)

    @objc func saveOfflineTreks(_ call: CAPPluginCall) {
        let raw = call.jsObjectRepresentation
        DispatchQueue.main.async {
            let saved = Tr3kOfflineCache.save(raw)
            WidgetCenter.shared.reloadTimelines(ofKind: Tr3kOfflineCache.widgetKind)
            if #available(iOS 16.2, *) {
                Task { @MainActor in
                    Tr3kLiveActivityMirror.shared.noteOffline(raw)
                }
            }
            call.resolve(saved)
        }
    }

    @objc func getOfflineTreks(_ call: CAPPluginCall) {
        call.resolve(Tr3kOfflineCache.load(key: call.getString("key")))
    }

    @objc func clearOfflineTreks(_ call: CAPPluginCall) {
        let cleared = Tr3kOfflineCache.clear(key: call.getString("key"))
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: Tr3kOfflineCache.widgetKind)
            call.resolve(cleared)
        }
    }

    // MARK: Sign in with Apple (optional, not required to launch)

    @objc func getAppleSession(_ call: CAPPluginCall) {
        call.resolve(Tr3kAppleSession.payload())
    }

    @objc func signOutApple(_ call: CAPPluginCall) {
        call.resolve(Tr3kAppleSession.clear())
    }

    @objc func signInWithApple(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if self.appleSignIn != nil {
                var payload = Tr3kAppleSession.payload()
                payload["reason"] = "in_progress"
                call.resolve(payload)
                return
            }
            guard let presenter = self.topPresenter() else {
                var payload = Tr3kAppleSession.payload()
                payload["reason"] = "unavailable"
                payload["message"] = "Tr3k is not ready to show Sign in with Apple."
                call.resolve(payload)
                return
            }
            let flow = Tr3kAppleSignIn(presenter: presenter) { [weak self] payload in
                self?.appleSignIn = nil
                call.resolve(payload)
            }
            self.appleSignIn = flow
            flow.start()
        }
    }
}
