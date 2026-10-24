import ARKit
import Capacitor
import CoreLocation
import UIKit
import UserNotifications
import WebKit

@objc(Tr3kNativePlugin)
public class Tr3kNativePlugin: CAPPlugin, CAPBridgedPlugin, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
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

    private static let regionPrefix = "tr3k-stop-"
    private static let maxRegions = 20

    private var manager: CLLocationManager!
    private var pendingFixes: [CAPPluginCall] = []
    private var pendingAuth: [CAPPluginCall] = []
    private var watching = false
    private var arrivalTitle = "You've arrived at a Tr3k stop"
    private var arrivalBody = "Open Tr3k to check in."
    private var stopNames: [String: String] = [:]
    private var mapController: Tr3kNativeMapController?

    override public func load() {
        DispatchQueue.main.async {
            self.manager = CLLocationManager()
            self.manager.delegate = self
            self.manager.desiredAccuracy = kCLLocationAccuracyBest
            self.manager.distanceFilter = kCLDistanceFilterNone
            self.manager.activityType = .fitness
            UNUserNotificationCenter.current().delegate = self
            self.injectShim()
        }
    }

    // MARK: JS shim

    private func injectShim() {
        guard let webView = bridge?.webView else { return }
        let script = WKUserScript(source: Tr3kNativeShim.source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)
        // Cover a page that already started loading before the plugin was ready.
        webView.evaluateJavaScript(Tr3kNativeShim.source, completionHandler: nil)
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
            let always = call.getBool("always") ?? false
            let status = self.authStatus()
            if status == .notDetermined {
                self.pendingAuth.append(call)
                self.manager.requestWhenInUseAuthorization()
            } else if always && status == .authorizedWhenInUse {
                self.pendingAuth.append(call)
                self.manager.requestAlwaysAuthorization()
            } else {
                call.resolve(["location": self.statusName(status)])
            }
        }
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
        if status != .notDetermined {
            let calls = pendingAuth
            pendingAuth.removeAll()
            calls.forEach { $0.resolve(["location": statusName(status)]) }
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
        DispatchQueue.main.async {
            guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
                call.resolve(["monitored": 0, "supported": false])
                return
            }
            if let t = call.getString("title"), !t.isEmpty { self.arrivalTitle = t }
            if let b = call.getString("body"), !b.isEmpty { self.arrivalBody = b }
            self.clearMonitoredRegions()
            let r = min(max(radius, 30), self.manager.maximumRegionMonitoringDistance)
            var count = 0
            for (i, stop) in stops.prefix(Tr3kNativePlugin.maxRegions).enumerated() {
                guard let lat = number(stop["lat"]) ?? number(stop["latitude"]),
                      let lng = number(stop["lng"]) ?? number(stop["lon"]) ?? number(stop["longitude"]) else { continue }
                let rawId = (stop["id"] as? String) ?? number(stop["id"]).map { String(Int($0)) } ?? String(i)
                let id = Tr3kNativePlugin.regionPrefix + rawId
                let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lng), radius: r, identifier: id)
                region.notifyOnEntry = true
                region.notifyOnExit = false
                if let name = stop["name"] as? String { self.stopNames[id] = name }
                self.manager.startMonitoring(for: region)
                count += 1
            }
            // Region monitoring only fires with "Always" access; ask for the upgrade.
            if self.authStatus() == .authorizedWhenInUse || self.authStatus() == .notDetermined {
                self.manager.requestAlwaysAuthorization()
            }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            call.resolve(["monitored": count, "supported": true, "location": self.statusName(self.authStatus())])
        }
    }

    @objc func clearStops(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.clearMonitoredRegions()
            call.resolve()
        }
    }

    private func clearMonitoredRegions() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Tr3kNativePlugin.regionPrefix) {
            manager.stopMonitoring(for: region)
        }
        stopNames.removeAll()
    }

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix(Tr3kNativePlugin.regionPrefix) else { return }
        let stopId = String(region.identifier.dropFirst(Tr3kNativePlugin.regionPrefix.count))
        let content = UNMutableNotificationContent()
        content.title = arrivalTitle
        if let name = stopNames[region.identifier] { content.subtitle = name }
        content.body = arrivalBody
        content.sound = .default
        content.userInfo = ["tr3kStopId": stopId]
        let request = UNNotificationRequest(identifier: "arrival-\(region.identifier)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        notifyListeners("arrival", data: ["stopId": stopId], retainUntilConsumed: true)
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        notifyListeners("locationError", data: ["message": "Stop alert failed: \(error.localizedDescription)"])
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
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

private func number(_ value: Any?) -> Double? {
    switch value {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s)
    default: return nil
    }
}
