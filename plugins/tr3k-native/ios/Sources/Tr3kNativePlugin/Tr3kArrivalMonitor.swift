import CoreLocation
import Foundation
import UIKit
import UserNotifications

/// Region monitoring for Tr3k stop arrival alerts.
///
/// The system keeps registered regions after the process is killed and relaunches
/// the app to deliver `didEnterRegion`. `prepareForRelaunch()` runs from
/// `application(_:didFinishLaunchingWithOptions:)` so a delegate exists before that
/// event is dropped. When In Use location (the map and the GPS watch) does not
/// depend on this monitor.
@objc(Tr3kArrivalMonitor)
public final class Tr3kArrivalMonitor: NSObject, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    public static let shared = Tr3kArrivalMonitor()

    /// Fired on the main queue. The plugin forwards this to the web view.
    var onArrival: ((String) -> Void)? {
        didSet { flushPendingArrivals() }
    }

    static let regionPrefix = "tr3k-stop-"
    private static let maxRegions = 20
    private static let storageKey = "tr3k.arrival.v1"
    private static let defaultTitle = "You've arrived at a Tr3k stop"
    private static let defaultBody = "Open Tr3k to check in."

    private var manager: CLLocationManager?
    private var started = false
    private var title = Tr3kArrivalMonitor.defaultTitle
    private var body = Tr3kArrivalMonitor.defaultBody
    private var radius: Double = 75
    private var stops: [Stop] = []
    private var pendingArrivals: [String] = []

    private struct Stop: Codable {
        var id: String
        var name: String?
        var lat: Double
        var lng: Double
    }

    private struct Stored: Codable {
        var title: String
        var body: String
        var radius: Double
        var stops: [Stop]
    }

    private override init() {
        super.init()
    }

    /// Safe to call more than once. Must run on the main thread when possible.
    @objc public static func prepareForRelaunch() {
        if Thread.isMainThread {
            shared.start()
        } else {
            DispatchQueue.main.async {
                shared.start()
            }
        }
    }

    func start() {
        if started { return }
        started = true
        restore()
        let manager = CLLocationManager()
        manager.activityType = .fitness
        // Continuous GPS stays on the plugin's other manager. This one only
        // watches stop regions, so the blue background pill is not required.
        manager.pausesLocationUpdatesAutomatically = true
        self.manager = manager
        manager.delegate = self
        UNUserNotificationCenter.current().delegate = self
        applyBackgroundUpdatesFlag()
        reapplyRegions()
    }

    /// Replace the monitored stops. Regions are armed only with Always authorization.
    /// The desired set is stored either way so a later Always grant can arm them.
    func replaceStops(_ rawStops: [[String: Any]], radius: Double, title: String?, body: String?) -> [String: Any] {
        start()
        if let title, !title.isEmpty { self.title = title }
        if let body, !body.isEmpty { self.body = body }
        self.radius = radius
        var parsed: [Stop] = []
        for (index, stop) in rawStops.prefix(Tr3kArrivalMonitor.maxRegions).enumerated() {
            guard let lat = Self.number(stop["lat"]) ?? Self.number(stop["latitude"]),
                  let lng = Self.number(stop["lng"]) ?? Self.number(stop["lon"]) ?? Self.number(stop["longitude"]) else {
                continue
            }
            let rawId = (stop["id"] as? String) ?? Self.number(stop["id"]).map { String(Int($0)) } ?? String(index)
            let name = stop["name"] as? String
            parsed.append(Stop(id: rawId, name: name, lat: lat, lng: lng))
        }
        stops = parsed
        persist()
        let armed = reapplyRegions()
        let supported = CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
        return [
            "monitored": armed,
            "pending": parsed.count,
            "supported": supported
        ]
    }

    func clear() {
        start()
        stops = []
        title = Tr3kArrivalMonitor.defaultTitle
        body = Tr3kArrivalMonitor.defaultBody
        persist()
        stopOwnedRegions()
    }

    // MARK: CLLocationManagerDelegate

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        applyBackgroundUpdatesFlag()
        reapplyRegions()
    }

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix(Tr3kArrivalMonitor.regionPrefix) else { return }
        let stopId = String(region.identifier.dropFirst(Tr3kArrivalMonitor.regionPrefix.count))
        postNotification(stopId: stopId, regionId: region.identifier)
        deliver(stopId: stopId)
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        // When In Use cannot arm regions. The stops stay stored and arm after Always.
        if let clErr = error as? CLError, clErr.code == .denied { return }
    }

    // MARK: Notifications

    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        if let stopId = response.notification.request.content.userInfo["tr3kStopId"] as? String {
            deliver(stopId: stopId)
        }
        completionHandler()
    }

    // MARK: Private

    @discardableResult
    private func reapplyRegions() -> Int {
        guard let manager else { return 0 }
        stopOwnedRegions()
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return 0 }
        guard manager.authorizationStatus == .authorizedAlways else { return 0 }
        let limit = manager.maximumRegionMonitoringDistance
        let clamped = min(max(radius, 30), limit > 0 ? limit : radius)
        var armed = 0
        for stop in stops {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng),
                radius: clamped,
                identifier: Tr3kArrivalMonitor.regionPrefix + stop.id
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
            armed += 1
        }
        return armed
    }

    private func stopOwnedRegions() {
        guard let manager else { return }
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Tr3kArrivalMonitor.regionPrefix) {
            manager.stopMonitoring(for: region)
        }
    }

    private func applyBackgroundUpdatesFlag() {
        guard let manager else { return }
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        let allows = modes?.contains("location") == true && manager.authorizationStatus == .authorizedAlways
        // Setting this true without the location background mode throws.
        manager.allowsBackgroundLocationUpdates = allows
    }

    private func postNotification(stopId: String, regionId: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let name = stops.first(where: { $0.id == stopId })?.name, !name.isEmpty {
            content.subtitle = name
        }
        content.body = body
        content.sound = .default
        content.userInfo = ["tr3kStopId": stopId]
        let stamp = Int(Date().timeIntervalSince1970)
        let request = UNNotificationRequest(identifier: "arrival-\(regionId)-\(stamp)", content: content, trigger: nil)
        let application = UIApplication.shared
        var task: UIBackgroundTaskIdentifier = .invalid
        task = application.beginBackgroundTask(withName: "tr3k-arrival") {
            if task != .invalid {
                application.endBackgroundTask(task)
            }
        }
        UNUserNotificationCenter.current().add(request) { _ in
            if task != .invalid {
                application.endBackgroundTask(task)
            }
        }
    }

    private func deliver(stopId: String) {
        let send = {
            if let onArrival = self.onArrival {
                onArrival(stopId)
            } else {
                self.pendingArrivals.append(stopId)
            }
        }
        if Thread.isMainThread {
            send()
        } else {
            DispatchQueue.main.async(execute: send)
        }
    }

    private func flushPendingArrivals() {
        guard onArrival != nil else { return }
        let queued = pendingArrivals
        pendingArrivals.removeAll()
        queued.forEach { onArrival?($0) }
    }

    private func persist() {
        let stored = Stored(title: title, body: body, radius: radius, stops: stops)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: Tr3kArrivalMonitor.storageKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Tr3kArrivalMonitor.storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        title = stored.title.isEmpty ? Tr3kArrivalMonitor.defaultTitle : stored.title
        body = stored.body.isEmpty ? Tr3kArrivalMonitor.defaultBody : stored.body
        radius = stored.radius
        stops = stored.stops
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: return double
        case let int as Int: return Double(int)
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        default: return nil
        }
    }
}
