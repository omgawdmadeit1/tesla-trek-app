import Capacitor
import CoreLocation
import MapKit
import UIKit

/// Plugin-owned MapKit map for in-Tr3k navigation.
///
/// The MKMapView sits above the WKWebView, inset from the webview edges. Touches
/// outside that frame stay on the page, so header and footer chrome keep working.
/// Optional `holes` (viewport CSS pixels, which are points on iOS) are masked out
/// of the map and pass touches through to HTML floating controls.
///
/// Pitch uses MKMapCamera. On iOS 16+ the map configuration uses realistic
/// elevation, which is Apple's Flyover-class terrain and 3D buildings where the
/// device and city data support them. This does not use MapKit JS or a token.
///
/// JS surface: plugins/tr3k-native/README.md (`window.tr3kNative`, shim version 5).
final class Tr3kNativeMapController: NSObject, MKMapViewDelegate {
    var onEvent: ((String, [String: Any], Bool) -> Void)?
    /// follow, followHeading
    var onFollowNeedsLocation: ((Bool, Bool) -> Void)?
    var fallbackCoordinate: (() -> CLLocationCoordinate2D?)?

    private(set) var wantsFollow = false
    private(set) var wantsFollowHeading = false

    private let host = Tr3kMapHostView()
    private let mapView = MKMapView(frame: .zero)
    private var edgeConstraints: [NSLayoutConstraint] = []
    private var insets = UIEdgeInsets.zero
    private var viewportHoles: [CGRect] = []
    private var kind: Tr3kMapKind = .standard
    private var visible = false
    private var didCreateMap = false
    private var didApplyInitialCamera = false
    private var hasFollowAnchor = false
    private var followZoom = 16.0
    private var followPitch: CGFloat = 55
    private var resumeFollow = false
    private var resumeFollowHeading = false
    private var fieldOfView: Double?
    private var programmatic = false
    private var moveToken = 0
    private var lastLocation: CLLocation?
    private var lastHeading: CLLocationDirection?
    private var lastFollowMove = Date.distantPast
    private var cameraEmitScheduled = false
    private var hookedPans = NSHashTable<UIPanGestureRecognizer>.weakObjects()
    private let backupPan = UIPanGestureRecognizer()
    private var installedBackupPan = false

    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var routeStops: [Tr3kMapStop] = []
    private var casingLine: MKPolyline?
    private var routeLine: MKPolyline?
    private var stopAnnotations: [Tr3kStopAnnotation] = []

    override init() {
        super.init()
        host.owner = self
        host.backgroundColor = .clear
        host.isOpaque = false
        host.clipsToBounds = true
        host.onLayout = { [weak self] in
            self?.hostDidLayout()
        }

        mapView.delegate = self
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.showsCompass = true
        mapView.showsUserLocation = true
        mapView.overrideUserInterfaceStyle = .dark
        mapView.backgroundColor = Tr3kMapKind.backdrop
        mapView.accessibilityLabel = "Tr3k map"
        host.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: host.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        apply(kind: .standard)
        didCreateMap = true
    }

    // MARK: JS operations

    func show(in parent: UIView, above sibling: UIView, options: JSObject) -> [String: Any] {
        if let nextInsets = edgeInsets(from: options) {
            insets = nextInsets
        }
        if let holes = holes(from: options) {
            viewportHoles = holes
        }
        if let raw = string(options, "mapType") ?? string(options, "type") {
            apply(kind: Tr3kMapKind(parsing: raw))
        }
        attach(parent: parent, above: sibling)
        visible = true
        parent.layoutIfNeeded()
        host.layoutIfNeeded()
        calibrateFovIfNeeded()
        hookPanGestures()
        ensureBackupPan()
        updateHoles()

        if let zoom = double(options["zoom"]) {
            followZoom = min(21, max(2, zoom))
        }
        if let pitch = double(options["pitch"]) {
            followPitch = CGFloat(clampedPitch(pitch))
        }
        let hasExplicitCenter = coordinate(in: options) != nil
        let knownLocation = fallbackCoordinate?() ?? lastLocation?.coordinate
        // Without a center or a GPS fix, leave the default camera alone. The first
        // follow update places the user at followZoom / followPitch.
        if hasExplicitCenter || (!didApplyInitialCamera && knownLocation != nil) || (didApplyInitialCamera && hasCameraKeys(options)) {
            var cameraOptions = options
            if double(cameraOptions["pitch"]) == nil && !didApplyInitialCamera {
                cameraOptions["pitch"] = Double(followPitch)
            }
            if double(cameraOptions["zoom"]) == nil
                && double(cameraOptions["distance"]) == nil
                && object(cameraOptions, "span") == nil
                && !didApplyInitialCamera {
                cameraOptions["zoom"] = followZoom
            }
            applyCamera(options: cameraOptions, animated: boolean(options, "animated") ?? false, pauseFollowOnCenter: false)
        } else if !didApplyInitialCamera {
            didApplyInitialCamera = true
        }

        applyRouteToMap()

        if let follow = boolean(options, "follow") {
            setFollow(on: follow, heading: boolean(options, "followHeading") ?? false, emitPause: false)
        } else if resumeFollow && coordinate(in: options) == nil {
            setFollow(on: true, heading: resumeFollowHeading, emitPause: false)
        }
        resumeFollow = false
        resumeFollowHeading = false

        let snap = snapshot()
        onEvent?("mapReady", snap, false)
        scheduleCameraEvent()
        return snap
    }

    func hide() -> [String: Any] {
        resumeFollow = wantsFollow
        resumeFollowHeading = wantsFollowHeading
        if wantsFollow || wantsFollowHeading {
            wantsFollow = false
            wantsFollowHeading = false
            onFollowNeedsLocation?(false, false)
        }
        visible = false
        host.removeFromSuperview()
        var snap = snapshot()
        snap["visible"] = false
        return snap
    }

    func setMapType(_ raw: String?) -> [String: Any] {
        apply(kind: Tr3kMapKind(parsing: raw))
        return snapshot()
    }

    func setCamera(options: JSObject) -> [String: Any] {
        guard didCreateMap else { return ["visible": false, "applied": false] }
        applyCamera(options: options, animated: boolean(options, "animated") ?? true, pauseFollowOnCenter: true)
        return snapshot()
    }

    func setFollow(on: Bool, heading: Bool) -> [String: Any] {
        setFollow(on: on, heading: heading, emitPause: false)
        return snapshot()
    }

    func setFollow(options: JSObject) -> [String: Any] {
        let on = boolean(options, "follow") ?? false
        let heading = boolean(options, "followHeading") ?? false
        return setFollow(on: on, heading: heading)
    }

    func resetNorth() -> [String: Any] {
        if wantsFollowHeading {
            wantsFollowHeading = false
            onFollowNeedsLocation?(wantsFollow, false)
        }
        let current = mapView.camera
        let next = MKMapCamera(
            lookingAtCenter: current.centerCoordinate,
            fromDistance: max(current.centerCoordinateDistance, 80),
            pitch: current.pitch,
            heading: 0
        )
        beginProgrammaticMove()
        mapView.setCamera(next, animated: true)
        return snapshot()
    }

    func zoom(by delta: Double) -> [String: Any] {
        guard didCreateMap else { return ["visible": false, "applied": false] }
        let next = min(21, max(2, currentZoom() + delta))
        var options: JSObject = [:]
        options["zoom"] = next
        options["animated"] = true
        applyCamera(options: options, animated: true, pauseFollowOnCenter: false)
        return snapshot()
    }

    func setLayout(options: JSObject) -> [String: Any] {
        if let nextInsets = edgeInsets(from: options) {
            insets = nextInsets
            updateInsetConstants()
        }
        if let holes = holes(from: options) {
            viewportHoles = holes
            updateHoles()
        }
        host.superview?.layoutIfNeeded()
        return snapshot()
    }

    func setRoute(options: JSObject) -> [String: Any] {
        if let raw = options["coordinates"] {
            routeCoordinates = coordinates(from: raw)
        }
        if let raw = options["stops"] {
            routeStops = stops(from: raw)
        }
        applyRouteToMap()
        let fit = boolean(options, "fit") ?? false
        if fit && !wantsFollow {
            fitRoute()
        }
        var snap = snapshot()
        snap["points"] = routeCoordinates.count
        snap["stops"] = routeStops.count
        return snap
    }

    func clearRoute() -> [String: Any] {
        routeCoordinates = []
        routeStops = []
        applyRouteToMap()
        var snap = snapshot()
        snap["points"] = 0
        snap["stops"] = 0
        return snap
    }

    func ingest(location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 150 else { return }
        lastLocation = location
        guard wantsFollow, visible, !programmatic, !userIsGesturing() else { return }
        if Date().timeIntervalSince(lastFollowMove) < 0.4 { return }
        let heading = wantsFollowHeading ? lastHeading : nil
        moveFollowCamera(to: location.coordinate, heading: heading)
    }

    func ingest(heading: CLLocationDirection) {
        guard heading >= 0 else { return }
        lastHeading = heading
        guard wantsFollow, wantsFollowHeading, visible, !programmatic, !userIsGesturing() else { return }
        guard let coordinate = lastLocation?.coordinate ?? fallbackCoordinate?() else { return }
        if Date().timeIntervalSince(lastFollowMove) < 0.25 { return }
        moveFollowCamera(to: coordinate, heading: heading)
    }

    func userPanned(_ gesture: UIPanGestureRecognizer) {
        guard wantsFollow, visible else { return }
        guard gesture.state == .began || gesture.state == .changed else { return }
        if gesture.numberOfTouches > 1 { return }
        let translation = gesture.translation(in: mapView)
        if hypot(translation.x, translation.y) < 16 { return }
        wantsFollow = false
        wantsFollowHeading = false
        resumeFollow = false
        resumeFollowHeading = false
        onFollowNeedsLocation?(false, false)
        var snap = snapshot()
        snap["reason"] = "pan"
        onEvent?("followPaused", snap, false)
    }

    // MARK: Map

    private func attach(parent: UIView, above sibling: UIView) {
        host.translatesAutoresizingMaskIntoConstraints = false
        if host.superview !== parent {
            host.removeFromSuperview()
            parent.insertSubview(host, aboveSubview: sibling)
        } else {
            parent.insertSubview(host, aboveSubview: sibling)
        }
        NSLayoutConstraint.deactivate(edgeConstraints)
        edgeConstraints = [
            host.topAnchor.constraint(equalTo: sibling.topAnchor, constant: insets.top),
            host.leadingAnchor.constraint(equalTo: sibling.leadingAnchor, constant: insets.left),
            host.trailingAnchor.constraint(equalTo: sibling.trailingAnchor, constant: -insets.right),
            host.bottomAnchor.constraint(equalTo: sibling.bottomAnchor, constant: -insets.bottom)
        ]
        NSLayoutConstraint.activate(edgeConstraints)
    }

    private func updateInsetConstants() {
        guard edgeConstraints.count == 4 else { return }
        edgeConstraints[0].constant = insets.top
        edgeConstraints[1].constant = insets.left
        edgeConstraints[2].constant = -insets.right
        edgeConstraints[3].constant = -insets.bottom
    }

    private func apply(kind: Tr3kMapKind) {
        self.kind = kind
        if #available(iOS 16.0, *) {
            mapView.preferredConfiguration = kind.configuration()
        } else {
            mapView.mapType = kind.legacyType
        }
        mapView.overrideUserInterfaceStyle = .dark
    }

    private func applyCamera(options: JSObject, animated: Bool, pauseFollowOnCenter: Bool) {
        let current = mapView.camera
        let center: CLLocationCoordinate2D
        if let explicit = coordinate(in: options) {
            center = explicit
        } else if !didApplyInitialCamera {
            center = initialCenter(options)
        } else {
            center = current.centerCoordinate
        }
        let pitch = CGFloat(clampedPitch(double(options["pitch"]) ?? Double(current.pitch)))
        let heading = double(options["heading"]) ?? current.heading
        let distance = resolvedDistance(options: options, center: center, fallback: current.centerCoordinateDistance)
        let explicitCenter = coordinate(in: options) != nil

        let camera = MKMapCamera(
            lookingAtCenter: center,
            fromDistance: max(distance, 80),
            pitch: pitch,
            heading: heading
        )
        beginProgrammaticMove()
        mapView.setCamera(camera, animated: animated)
        didApplyInitialCamera = true
        hasFollowAnchor = true

        if pauseFollowOnCenter && explicitCenter && wantsFollow {
            wantsFollow = false
            wantsFollowHeading = false
            resumeFollow = false
            resumeFollowHeading = false
            onFollowNeedsLocation?(false, false)
            var snap = snapshot()
            snap["reason"] = "camera"
            onEvent?("followPaused", snap, false)
        }
    }

    private func setFollow(on: Bool, heading: Bool, emitPause: Bool) {
        let wasFollowing = wantsFollow
        wantsFollow = on
        wantsFollowHeading = on && heading
        if !on {
            resumeFollow = false
            resumeFollowHeading = false
        }
        onFollowNeedsLocation?(wantsFollow, wantsFollowHeading)
        if on, let coordinate = lastLocation?.coordinate ?? fallbackCoordinate?() {
            moveFollowCamera(to: coordinate, heading: wantsFollowHeading ? lastHeading : nil)
        }
        if emitPause && wasFollowing && !on {
            var snap = snapshot()
            snap["reason"] = "api"
            onEvent?("followPaused", snap, false)
        }
    }

    private func moveFollowCamera(to coordinate: CLLocationCoordinate2D, heading: CLLocationDirection?) {
        let current = mapView.camera
        let nextHeading = heading ?? current.heading
        let distance: CLLocationDistance
        let pitch: CGFloat
        if hasFollowAnchor {
            distance = max(current.centerCoordinateDistance, 80)
            pitch = current.pitch
        } else {
            distance = self.distance(forZoom: followZoom, latitude: coordinate.latitude)
            pitch = followPitch
            hasFollowAnchor = true
        }
        let camera = MKMapCamera(
            lookingAtCenter: coordinate,
            fromDistance: distance,
            pitch: pitch,
            heading: nextHeading
        )
        lastFollowMove = Date()
        beginProgrammaticMove()
        mapView.setCamera(camera, animated: true)
    }

    private func beginProgrammaticMove() {
        moveToken += 1
        let token = moveToken
        programmatic = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, self.moveToken == token else { return }
            self.programmatic = false
        }
    }

    private func hostDidLayout() {
        calibrateFovIfNeeded()
        hookPanGestures()
        updateHoles()
    }

    private func updateHoles() {
        let rects = viewportHoles.map { hole in
            CGRect(
                x: hole.origin.x - insets.left,
                y: hole.origin.y - insets.top,
                width: hole.width,
                height: hole.height
            )
        }
        host.passThrough = rects
        mapView.isOpaque = rects.isEmpty
        guard mapView.bounds.width > 1, mapView.bounds.height > 1 else {
            mapView.layer.mask = nil
            return
        }
        guard !rects.isEmpty else {
            mapView.layer.mask = nil
            return
        }
        let path = UIBezierPath(rect: mapView.bounds)
        for hole in rects {
            path.append(UIBezierPath(rect: hole))
        }
        let mask = CAShapeLayer()
        mask.frame = mapView.bounds
        mask.fillRule = .evenOdd
        mask.path = path.cgPath
        mapView.layer.mask = mask
    }

    private func hookPanGestures() {
        for case let pan as UIPanGestureRecognizer in collectGestures(mapView) {
            if pan === backupPan || hookedPans.contains(pan) { continue }
            pan.addTarget(host, action: #selector(Tr3kMapHostView.mapPanned(_:)))
            hookedPans.add(pan)
        }
    }

    private func ensureBackupPan() {
        guard !installedBackupPan else { return }
        installedBackupPan = true
        backupPan.cancelsTouchesInView = false
        backupPan.delaysTouchesBegan = false
        backupPan.maximumNumberOfTouches = 1
        backupPan.delegate = host
        backupPan.addTarget(host, action: #selector(Tr3kMapHostView.mapPanned(_:)))
        mapView.addGestureRecognizer(backupPan)
    }

    private func collectGestures(_ view: UIView, depth: Int = 0) -> [UIGestureRecognizer] {
        var found = view.gestureRecognizers ?? []
        if depth < 4 {
            for subview in view.subviews {
                found.append(contentsOf: collectGestures(subview, depth: depth + 1))
            }
        }
        return found
    }

    private func userIsGesturing() -> Bool {
        for gesture in collectGestures(mapView) {
            if gesture.state == .began || gesture.state == .changed { return true }
        }
        return false
    }

    // MARK: Route

    private func applyRouteToMap() {
        if let casingLine { mapView.removeOverlay(casingLine) }
        if let routeLine { mapView.removeOverlay(routeLine) }
        casingLine = nil
        routeLine = nil
        if !stopAnnotations.isEmpty {
            mapView.removeAnnotations(stopAnnotations)
            stopAnnotations = []
        }
        if routeCoordinates.count >= 2 {
            var coords = routeCoordinates
            let casing = MKPolyline(coordinates: &coords, count: coords.count)
            var strokeCoords = routeCoordinates
            let stroke = MKPolyline(coordinates: &strokeCoords, count: strokeCoords.count)
            casingLine = casing
            routeLine = stroke
            mapView.addOverlay(casing)
            mapView.addOverlay(stroke)
        }
        var annotations: [Tr3kStopAnnotation] = []
        for stop in routeStops {
            let pin = Tr3kStopAnnotation(stop: stop)
            annotations.append(pin)
        }
        stopAnnotations = annotations
        if !annotations.isEmpty {
            mapView.addAnnotations(annotations)
        }
    }

    private func fitRoute() {
        var rect: MKMapRect?
        if let routeLine {
            rect = routeLine.boundingMapRect
        }
        for stop in routeStops {
            let point = MKMapPoint(stop.coordinate)
            let stopRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
            rect = rect.map { $0.union(stopRect) } ?? stopRect
        }
        guard var rect else { return }
        if rect.size.width < 1 { rect.size.width = 1 }
        if rect.size.height < 1 { rect.size.height = 1 }
        let pitch = mapView.camera.pitch
        let heading = mapView.camera.heading
        beginProgrammaticMove()
        mapView.setVisibleMapRect(
            rect,
            edgePadding: UIEdgeInsets(top: 56, left: 40, bottom: 56, right: 40),
            animated: false
        )
        let fitted = mapView.camera
        let camera = MKMapCamera(
            lookingAtCenter: fitted.centerCoordinate,
            fromDistance: max(fitted.centerCoordinateDistance, 80),
            pitch: pitch,
            heading: heading
        )
        mapView.setCamera(camera, animated: false)
    }

    // MARK: Camera math

    private var viewport: CGSize {
        let bounds = mapView.bounds
        if bounds.width > 1 && bounds.height > 1 { return bounds.size }
        return CGSize(width: 390, height: 844)
    }

    private var fov: Double {
        fieldOfView ?? (30 * .pi / 180)
    }

    private func calibrateFovIfNeeded() {
        guard fieldOfView == nil else { return }
        guard mapView.bounds.height > 1, mapView.camera.pitch < 5 else { return }
        let lat = mapView.centerCoordinate.latitude
        let metersHigh = MKMetersPerMapPointAtLatitude(lat) * mapView.visibleMapRect.size.height
        let distance = mapView.camera.centerCoordinateDistance
        guard metersHigh > 10, distance > 10 else { return }
        let angle = 2 * atan((metersHigh * 0.5) / distance)
        if angle > 0.2 && angle < 1.6 {
            fieldOfView = angle
        }
    }

    private func distance(forZoom zoom: Double, latitude: Double) -> CLLocationDistance {
        let clamped = min(21, max(2, zoom))
        let size = viewport
        let lngDelta = 360.0 * Double(size.width) / (256.0 * pow(2.0, clamped))
        let latDelta = lngDelta * Double(size.height) / Double(max(size.width, 1))
        let lat = min(85, max(-85, latitude))
        let north = CLLocation(latitude: min(90, lat + latDelta / 2), longitude: 0)
        let south = CLLocation(latitude: max(-90, lat - latDelta / 2), longitude: 0)
        let metersHigh = max(north.distance(from: south), 20)
        return max(80, (metersHigh * 0.5) / tan(fov / 2))
    }

    private func currentZoom() -> Double {
        let distance = max(mapView.camera.centerCoordinateDistance, 80)
        let metersHigh = 2 * distance * tan(fov / 2)
        let latDelta = max(metersHigh / 111_320.0, 1e-8)
        let size = viewport
        let lngDelta = latDelta * Double(size.width) / Double(max(size.height, 1))
        return min(21, max(2, log2(360.0 * Double(size.width) / (256.0 * lngDelta))))
    }

    private func resolvedDistance(options: JSObject, center: CLLocationCoordinate2D, fallback: CLLocationDistance) -> CLLocationDistance {
        if let distance = double(options["distance"]) {
            return max(80, distance)
        }
        if let zoom = double(options["zoom"]) {
            return distance(forZoom: zoom, latitude: center.latitude)
        }
        if let span = object(options, "span"),
           let latDelta = double(span["latitudeDelta"]), latDelta > 0 {
            let lat = min(85, max(-85, center.latitude))
            let north = CLLocation(latitude: min(90, lat + latDelta / 2), longitude: center.longitude)
            let south = CLLocation(latitude: max(-90, lat - latDelta / 2), longitude: center.longitude)
            let metersHigh = max(north.distance(from: south), 20)
            return max(80, (metersHigh * 0.5) / tan(fov / 2))
        }
        return max(fallback, 80)
    }

    private func clampedPitch(_ pitch: Double) -> Double {
        min(80, max(0, pitch))
    }

    private func initialCenter(_ options: JSObject) -> CLLocationCoordinate2D {
        if let coordinate = coordinate(in: options) { return coordinate }
        if let fallback = fallbackCoordinate?() { return fallback }
        if let last = lastLocation?.coordinate { return last }
        return mapView.centerCoordinate
    }

    private func hasCameraKeys(_ options: JSObject) -> Bool {
        if coordinate(in: options) != nil { return true }
        if double(options["zoom"]) != nil { return true }
        if double(options["pitch"]) != nil { return true }
        if double(options["heading"]) != nil { return true }
        if double(options["distance"]) != nil { return true }
        if object(options, "span") != nil { return true }
        return false
    }

    private func scheduleCameraEvent() {
        guard !cameraEmitScheduled else { return }
        cameraEmitScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.cameraEmitScheduled = false
            guard self.visible else { return }
            self.onEvent?("cameraChanged", self.snapshot(), false)
        }
    }

    private func snapshot() -> [String: Any] {
        let center = mapView.centerCoordinate
        let span = mapView.region.span
        return [
            "visible": visible,
            "mapType": kind.rawValue,
            "latitude": center.latitude,
            "longitude": center.longitude,
            "center": [
                "lat": center.latitude,
                "lng": center.longitude
            ] as [String: Any],
            "zoom": currentZoom(),
            "pitch": Double(mapView.camera.pitch),
            "heading": mapView.camera.heading,
            "follow": wantsFollow,
            "followHeading": wantsFollowHeading,
            "latitudeDelta": span.latitudeDelta,
            "longitudeDelta": span.longitudeDelta,
            "insets": [
                "top": Double(insets.top),
                "right": Double(insets.right),
                "bottom": Double(insets.bottom),
                "left": Double(insets.left)
            ] as [String: Any]
        ]
    }

    // MARK: MKMapViewDelegate

    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        hookPanGestures()
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        programmatic = false
        scheduleCameraEvent()
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let line = overlay as? MKPolyline else {
            return MKOverlayRenderer(overlay: overlay)
        }
        let renderer = MKPolylineRenderer(polyline: line)
        renderer.lineCap = .round
        renderer.lineJoin = .round
        if overlay === casingLine {
            renderer.strokeColor = UIColor(red: 0.08, green: 0.06, blue: 0.04, alpha: 0.9)
            renderer.lineWidth = 9
        } else {
            renderer.strokeColor = UIColor(red: 0.98, green: 0.62, blue: 0.22, alpha: 0.96)
            renderer.lineWidth = 5
        }
        return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is Tr3kStopAnnotation else { return nil }
        let identifier = "tr3k-stop"
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        view.annotation = annotation
        view.markerTintColor = UIColor(red: 0.91, green: 0.42, blue: 0.16, alpha: 1)
        view.glyphTintColor = .white
        view.titleVisibility = .adaptive
        view.subtitleVisibility = .adaptive
        view.canShowCallout = true
        view.displayPriority = .required
        return view
    }
}

// MARK: - Host

final class Tr3kMapHostView: UIView, UIGestureRecognizerDelegate {
    weak var owner: Tr3kNativeMapController?
    var passThrough: [CGRect] = []
    var onLayout: (() -> Void)?
    private var adjustingZOrder = false

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if passThrough.contains(where: { $0.contains(point) }) { return false }
        return super.point(inside: point, with: event)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !adjustingZOrder, let superview, superview.subviews.last !== self {
            adjustingZOrder = true
            superview.bringSubviewToFront(self)
            adjustingZOrder = false
        }
        onLayout?()
    }

    @objc func mapPanned(_ gesture: UIPanGestureRecognizer) {
        owner?.userPanned(gesture)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

// MARK: - Model

private enum Tr3kMapKind: String {
    case standard
    case satellite
    case hybrid
    case mutedStandard

    static let backdrop = UIColor(red: 20 / 255, green: 17 / 255, blue: 14 / 255, alpha: 1)

    init(parsing raw: String?) {
        switch raw?.replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "").lowercased() {
        case "satellite":
            self = .satellite
        case "hybrid":
            self = .hybrid
        case "muted", "mutedstandard":
            self = .mutedStandard
        default:
            self = .standard
        }
    }

    var legacyType: MKMapType {
        switch self {
        case .standard: return .standard
        case .satellite: return .satellite
        case .hybrid: return .hybrid
        case .mutedStandard: return .mutedStandard
        }
    }

    @available(iOS 16.0, *)
    func configuration() -> MKMapConfiguration {
        switch self {
        case .standard:
            return MKStandardMapConfiguration(
                elevationStyle: MKMapConfiguration.ElevationStyle.realistic,
                emphasisStyle: MKStandardMapConfiguration.EmphasisStyle.default
            )
        case .mutedStandard:
            return MKStandardMapConfiguration(
                elevationStyle: MKMapConfiguration.ElevationStyle.realistic,
                emphasisStyle: MKStandardMapConfiguration.EmphasisStyle.muted
            )
        case .satellite:
            return MKImageryMapConfiguration(elevationStyle: MKMapConfiguration.ElevationStyle.realistic)
        case .hybrid:
            return MKHybridMapConfiguration(elevationStyle: MKMapConfiguration.ElevationStyle.realistic)
        }
    }
}

private struct Tr3kMapStop {
    var id: String
    var name: String
    var coordinate: CLLocationCoordinate2D
}

private final class Tr3kStopAnnotation: NSObject, MKAnnotation {
    let stopId: String
    let title: String?
    let subtitle: String?
    let coordinate: CLLocationCoordinate2D

    init(stop: Tr3kMapStop) {
        stopId = stop.id
        title = stop.name.isEmpty ? "Tr3k stop" : stop.name
        subtitle = stop.name.isEmpty ? nil : "Tr3k stop"
        coordinate = stop.coordinate
    }
}

// MARK: - JS values

private func string(_ options: JSObject, _ key: String) -> String? {
    options[key] as? String
}

private func boolean(_ options: JSObject, _ key: String) -> Bool? {
    guard let value = options[key] else { return nil }
    if let bool = value as? Bool { return bool }
    // JSON booleans cross the bridge as CFBoolean, which is an NSNumber.
    // Numeric fields (zoom, heading, pitch) must not be read as flags.
    if let number = value as? NSNumber, CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
        return number.boolValue
    }
    return nil
}

private func double(_ value: JSValue?) -> Double? {
    switch value {
    case let value as Double:
        return value
    case let value as Int:
        return Double(value)
    case let value as NSNumber:
        return value.doubleValue
    case let value as String:
        return Double(value)
    default:
        return nil
    }
}

private func object(_ options: JSObject, _ key: String) -> JSObject? {
    options[key] as? JSObject
}

private func isValid(lat: Double, lng: Double) -> Bool {
    lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
}

private func coordinate(in options: JSObject) -> CLLocationCoordinate2D? {
    if let center = options["center"], let coordinate = coordinate(from: center) {
        return coordinate
    }
    if let lat = double(options["lat"]) ?? double(options["latitude"]),
       let lng = double(options["lng"]) ?? double(options["lon"]) ?? double(options["longitude"]),
       isValid(lat: lat, lng: lng) {
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    return nil
}

private func coordinate(from value: JSValue) -> CLLocationCoordinate2D? {
    if let pair = value as? JSArray {
        return coordinate(fromPair: pair)
    }
    if let pair = value as? NSArray {
        return coordinate(fromPair: pair.map { $0 as? JSValue ?? NSNull() })
    }
    if let obj = value as? JSObject {
        return coordinate(in: obj)
    }
    if let obj = value as? NSDictionary {
        var converted: JSObject = [:]
        for (key, raw) in obj {
            guard let key = key as? String else { continue }
            if let js = raw as? JSValue {
                converted[key] = js
            }
        }
        return coordinate(in: converted)
    }
    return nil
}

private func coordinate(fromPair pair: JSArray) -> CLLocationCoordinate2D? {
    guard pair.count >= 2, let lng = double(pair[0]), let lat = double(pair[1]), isValid(lat: lat, lng: lng) else {
        return nil
    }
    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
}

private func coordinates(from value: JSValue) -> [CLLocationCoordinate2D] {
    let rows: [JSValue]
    if let array = value as? JSArray {
        rows = array
    } else if let array = value as? NSArray {
        rows = array.compactMap { $0 as? JSValue }
    } else {
        return []
    }
    var coords: [CLLocationCoordinate2D] = []
    coords.reserveCapacity(min(rows.count, 5000))
    for row in rows {
        guard let coordinate = coordinate(from: row) else { continue }
        coords.append(coordinate)
        if coords.count >= 5000 { break }
    }
    return coords
}

private func stops(from value: JSValue) -> [Tr3kMapStop] {
    let rows: [JSValue]
    if let array = value as? JSArray {
        rows = array
    } else if let array = value as? NSArray {
        rows = array.compactMap { $0 as? JSValue }
    } else {
        return []
    }
    var stops: [Tr3kMapStop] = []
    for (index, row) in rows.enumerated() {
        guard let obj = row as? JSObject ?? (row as? NSDictionary).map(jsObject(from:)) else { continue }
        guard let coordinate = coordinate(in: obj) else { continue }
        let name = string(obj, "name") ?? ""
        let id = stopId(obj["id"], fallback: index)
        stops.append(Tr3kMapStop(id: id, name: name, coordinate: coordinate))
    }
    return stops
}

private func stopId(_ value: JSValue?, fallback: Int) -> String {
    if let value = value as? String, !value.isEmpty { return value }
    if let value = value as? Int { return String(value) }
    if let value = value as? NSNumber { return String(value.intValue) }
    return String(fallback)
}

private func jsObject(from dictionary: NSDictionary) -> JSObject {
    var converted: JSObject = [:]
    for (key, raw) in dictionary {
        guard let key = key as? String, let js = raw as? JSValue else { continue }
        converted[key] = js
    }
    return converted
}

private func edgeInsets(from options: JSObject) -> UIEdgeInsets? {
    guard let raw = object(options, "insets") else { return nil }
    return UIEdgeInsets(
        top: CGFloat(max(0, double(raw["top"]) ?? 0)),
        left: CGFloat(max(0, double(raw["left"]) ?? 0)),
        bottom: CGFloat(max(0, double(raw["bottom"]) ?? 0)),
        right: CGFloat(max(0, double(raw["right"]) ?? 0))
    )
}

private func holes(from options: JSObject) -> [CGRect]? {
    guard let raw = options["holes"] else { return nil }
    let rows: [JSValue]
    if let array = raw as? JSArray {
        rows = array
    } else if let array = raw as? NSArray {
        rows = array.compactMap { $0 as? JSValue }
    } else {
        return []
    }
    var rects: [CGRect] = []
    for row in rows {
        let obj: JSObject?
        if let dictionary = row as? JSObject {
            obj = dictionary
        } else if let dictionary = row as? NSDictionary {
            obj = jsObject(from: dictionary)
        } else {
            obj = nil
        }
        guard let obj else { continue }
        let width = double(obj["width"]) ?? 0
        let height = double(obj["height"]) ?? 0
        guard width > 0, height > 0 else { continue }
        rects.append(CGRect(
            x: double(obj["x"]) ?? 0,
            y: double(obj["y"]) ?? 0,
            width: width,
            height: height
        ))
    }
    return rects
}
