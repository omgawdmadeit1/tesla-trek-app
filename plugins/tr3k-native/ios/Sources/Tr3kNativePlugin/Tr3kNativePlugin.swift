import ARKit
import Capacitor
import CoreLocation
import Tr3kActivityKit
import UIKit
import UserNotifications
import WebKit

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
        CAPPluginMethod(name: "share", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getLastDeepLink", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "haptic", returnType: CAPPluginReturnPromise),
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
        CAPPluginMethod(name: "clearRoute", returnType: CAPPluginReturnPromise)
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
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        Tr3kArrivalMonitor.prepareForRelaunch()
        Tr3kArrivalMonitor.shared.onArrival = { [weak self] stopId in
            self?.notifyListeners("arrival", data: ["stopId": stopId], retainUntilConsumed: true)
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

    /// Region alerts keep working in the background. Continuous GPS does not.
    @objc private func appDidEnterBackground() {
        guard manager != nil else { return }
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
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
            if self.pendingFixes.isEmpty && self.mapController?.wantsFollow != true {
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
        if !watching && pendingFixes.isEmpty && mapController?.wantsFollow != true {
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

    @objc func startLiveActivity(_ call: CAPPluginCall) {
        let fields = call.jsObjectRepresentation
        Task { @MainActor in
            guard #available(iOS 16.2, *) else {
                call.resolve(["started": false, "reason": "unsupported"])
                return
            }
            guard Tr3kLiveActivityController.activitiesEnabled() else {
                call.resolve(["started": false, "reason": "disabled"])
                return
            }
            let trekId = Tr3kLiveActivityController.text(fields["trekId"]) ?? ""
            let trekName = Tr3kLiveActivityController.text(fields["trekName"]) ?? "Tr3k"
            do {
                let id = try await Tr3kLiveActivityController.start(trekId: trekId, trekName: trekName, fields: fields)
                call.resolve(["started": true, "id": id])
            } catch {
                call.resolve(["started": false, "reason": error.localizedDescription])
            }
        }
    }

    @objc func updateLiveActivity(_ call: CAPPluginCall) {
        let fields = call.jsObjectRepresentation
        Task { @MainActor in
            guard #available(iOS 16.2, *) else {
                call.resolve(["updated": false, "reason": "unsupported"])
                return
            }
            let updated = await Tr3kLiveActivityController.update(fields: fields)
            call.resolve(["updated": updated])
        }
    }

    @objc func endLiveActivity(_ call: CAPPluginCall) {
        let immediate = (call.getString("dismissal") ?? "immediate") != "default"
        Task { @MainActor in
            guard #available(iOS 16.2, *) else {
                call.resolve(["ended": false, "reason": "unsupported"])
                return
            }
            await Tr3kLiveActivityController.end(immediate: immediate)
            call.resolve(["ended": true])
        }
    }

    // MARK: AR pumpkin box

    @objc func isARSupported(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            call.resolve(["supported": ARWorldTrackingConfiguration.isSupported])
        }
    }

    @objc func openAR(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard ARWorldTrackingConfiguration.isSupported else {
                call.resolve(["opened": false, "reason": "unsupported"])
                return
            }
            guard let presenter = self.bridge?.viewController else {
                call.resolve(["opened": false, "reason": "not_ready"])
                return
            }
            let view = Tr3kPumpkinARViewController()
            view.modalPresentationStyle = .fullScreen
            view.tier = call.getString("tier") ?? "common"
            view.prize = call.getString("prize") ?? ""
            let tier = view.tier
            let prize = view.prize
            view.onFinish = { [weak presenter] opened, reason in
                let done = { call.resolve(["opened": opened, "reason": reason, "tier": tier, "prize": prize]) }
                if let presenter = presenter { presenter.dismiss(animated: true, completion: done) } else { done() }
            }
            presenter.present(view, animated: true)
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
            let snapshot = self.mapOnMain().show(in: parent, above: webView, options: call.jsObjectRepresentation)
            call.resolve(snapshot)
        }
    }

    @objc func hideMap(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let map = self.mapController else {
                call.resolve(["visible": false])
                return
            }
            call.resolve(map.hide())
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
        DispatchQueue.main.async {
            call.resolve(self.mapOnMain().setRoute(options: call.jsObjectRepresentation))
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
            if !watching && pendingFixes.isEmpty {
                manager.stopUpdatingLocation()
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
}
