import CoreLocation
import SwiftUI
import Tr3kAppGroup
import WidgetKit

struct Tr3kWidgetEntry: TimelineEntry {
    let date: Date
    let model: Tr3kWidgetModel
}

struct Tr3kWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> Tr3kWidgetEntry {
        Tr3kWidgetEntry(date: Date(), model: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (Tr3kWidgetEntry) -> Void) {
        if context.isPreview {
            completion(Tr3kWidgetEntry(date: Date(), model: .placeholder))
            return
        }
        let cached = Tr3kOfflineCache.snapshot()
        completion(Tr3kWidgetEntry(date: Date(), model: cached.gatedForSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Tr3kWidgetEntry>) -> Void) {
        let loader = Tr3kWidgetLoader()
        loader.load { model in
            let entry = Tr3kWidgetEntry(date: Date(), model: model)
            let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

/// One timeline refresh. Asks Core Location the same way the shell does, then
/// calls `/api/nearby`. A denied or empty result never throws.
final class Tr3kWidgetLoader: NSObject, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var completion: ((Tr3kWidgetModel) -> Void)?
    private var timeout: DispatchWorkItem?
    private var startedFetch = false
    private var kept: Tr3kWidgetLoader?

    func load(completion: @escaping (Tr3kWidgetModel) -> Void) {
        kept = self
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                completion(Tr3kOfflineCache.snapshot())
                return
            }
            self.completion = completion
            self.begin()
        }
    }

    private func begin() {
        let manager = CLLocationManager()
        self.manager = manager
        let status = manager.authorizationStatus
        remember(status)
        switch access(status) {
        case .blocked:
            finish(Tr3kOfflineCache.snapshot().withholdingNearby())
        case .allowed:
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                resolveCoordinate(manager)
            } else if let coordinate = Tr3kOfflineCache.lastCoordinate() {
                fetch(latitude: coordinate.latitude, longitude: coordinate.longitude)
            } else {
                let cached = Tr3kOfflineCache.snapshot()
                finish(cached.isEmpty ? cached.withholdingNearby() : cached)
            }
        }
    }

    private enum Access {
        case allowed
        case blocked
    }

    private func access(_ status: CLAuthorizationStatus) -> Access {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return .allowed
        case .denied, .restricted:
            return .blocked
        case .notDetermined:
            return storedAccess()
        @unknown default:
            return storedAccess()
        }
    }

    private func remember(_ status: CLAuthorizationStatus) {
        let name: String?
        switch status {
        case .authorizedAlways:
            name = "always"
        case .authorizedWhenInUse:
            name = "whenInUse"
        case .denied:
            name = "denied"
        case .restricted:
            name = "restricted"
        case .notDetermined:
            name = nil
        @unknown default:
            name = nil
        }
        if let name {
            Tr3kOfflineCache.noteLocationStatus(name)
        }
    }

    private func storedAccess() -> Access {
        let stored = Tr3kOfflineCache.locationStatus()
        if stored == "denied" || stored == "restricted" { return .blocked }
        if stored == "always" || stored == "whenInUse" { return .allowed }
        let cached = Tr3kOfflineCache.snapshot()
        if cached.isEmpty && Tr3kOfflineCache.lastCoordinate() == nil { return .blocked }
        return .allowed
    }

    private func resolveCoordinate(_ manager: CLLocationManager) {
        if let last = fresh(manager.location) {
            fetch(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
            return
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.startedFetch else { return }
            self.finishWithCachedCoordinate()
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
        manager.requestLocation()
    }

    private func fresh(_ location: CLLocation?) -> CLLocation? {
        guard let location, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 1_000 else { return nil }
        guard abs(location.timestamp.timeIntervalSinceNow) < 3600 else { return nil }
        return location
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard completion != nil, !startedFetch else { return }
        guard let location = locations.last, location.horizontalAccuracy >= 0 else {
            finishWithCachedCoordinate()
            return
        }
        fetch(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !startedFetch else { return }
        if let clError = error as? CLError, clError.code == .denied {
            finish(Tr3kOfflineCache.snapshot().withholdingNearby())
            return
        }
        finishWithCachedCoordinate()
    }

    private func finishWithCachedCoordinate() {
        guard completion != nil, !startedFetch else { return }
        if let coordinate = Tr3kOfflineCache.lastCoordinate() {
            fetch(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return
        }
        let cached = Tr3kOfflineCache.snapshot()
        if cached.isEmpty {
            finish(cached.withholdingNearby())
        } else {
            finish(cached)
        }
    }

    private func fetch(latitude: Double, longitude: Double) {
        guard !startedFetch else { return }
        startedFetch = true
        timeout?.cancel()
        let cached = Tr3kOfflineCache.snapshot()
        guard let request = Tr3kNearbyFeed.request(latitude: latitude, longitude: longitude) else {
            finish(cached.isEmpty ? cached.withholdingNearby() : cached)
            return
        }
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let pool: [[String: Any]]
            if code == 200, let data {
                pool = Tr3kNearbyFeed.parse(data, latitude: latitude, longitude: longitude)
            } else {
                pool = []
            }
            let model: Tr3kWidgetModel
            if pool.isEmpty {
                model = cached.isEmpty ? cached.withholdingNearby() : cached
            } else {
                model = Tr3kOfflineCache.replaceNearby(pool, latitude: latitude, longitude: longitude)
            }
            self?.finish(model)
        }.resume()
    }

    private func finish(_ model: Tr3kWidgetModel) {
        let deliver = {
            self.timeout?.cancel()
            self.timeout = nil
            self.manager?.delegate = nil
            let done = self.completion
            self.completion = nil
            done?(model)
            self.kept = nil
        }
        if Thread.isMainThread {
            deliver()
        } else {
            DispatchQueue.main.async(execute: deliver)
        }
    }
}

struct Tr3kHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Tr3kOfflineCache.widgetKind, provider: Tr3kWidgetProvider()) { entry in
            Tr3kWidgetView(entry: entry)
        }
        .configurationDisplayName("Tr3k")
        .description("Nearby Tr3ks, on the hour.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Tr3kWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Tr3kWidgetEntry

    private let gold = Color(red: 0.886, green: 0.647, blue: 0.227)
    private let paper = Color.white
    private let dim = Color.white.opacity(0.72)
    private let prompt = "Enable location for nearby Tr3ks"

    private var model: Tr3kWidgetModel { entry.model }

    private var showsPrompt: Bool {
        model.nearby.isEmpty && model.active == nil
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(model.primaryLink)
        .tr3kWidgetBackground()
    }

    private var wordmark: some View {
        Text("TR3K")
            .font(.system(size: 11, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(gold)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            wordmark
            Spacer(minLength: 0)
            Text(heroLine)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(paper)
                .lineLimit(4)
                .minimumScaleFactor(0.72)
            if let subtitle = heroSubtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(dim)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            Link(destination: model.primaryLink) {
                HStack(alignment: .firstTextBaseline) {
                    wordmark
                    Spacer(minLength: 8)
                    if !headerAction.isEmpty {
                        Text(headerAction)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(dim)
                    }
                }
            }
            if showsPrompt {
                Link(destination: model.primaryLink) {
                    Text(prompt)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(paper)
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                if let active = model.active {
                    Link(destination: active.link) {
                        Text("Continue · \(active.name)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(dim)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if model.nearby.isEmpty && model.needsLocation {
                    Link(destination: model.primaryLink) {
                        Text(prompt)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(paper)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if model.active == nil && model.nearby.count > 2 {
                    Text("\(model.nearby.count) Tr3ks near you")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(dim)
                        .lineLimit(1)
                }
                ForEach(nearbyRows) { ref in
                    Link(destination: ref.link) {
                        Text(ref.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(paper)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var nearbyRows: [Tr3kPlaceRef] {
        Array(model.nearby.prefix(2))
    }

    private var heroLine: String {
        if showsPrompt { return prompt }
        if model.nearby.count >= 2, let first = model.nearby.first {
            return "\(model.nearby.count) Tr3ks near you · \(first.name)"
        }
        if let only = model.nearby.first { return only.name }
        if let active = model.active { return active.name }
        return prompt
    }

    private var heroSubtitle: String? {
        if showsPrompt { return nil }
        if model.nearby.count == 1, let only = model.nearby.first {
            return only.place ?? only.category ?? only.gameCopy
        }
        if model.nearby.isEmpty, model.active != nil {
            return model.needsLocation ? prompt : "Continue"
        }
        return nil
    }

    private var headerAction: String {
        if !model.nearby.isEmpty { return "Play" }
        if model.active != nil { return "Continue" }
        return ""
    }
}

private extension View {
    @ViewBuilder
    func tr3kWidgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(Color.black, for: .widget)
        } else {
            background(Color.black)
        }
    }
}

@main
struct Tr3kWidgetBundle: WidgetBundle {
    var body: some Widget {
        Tr3kHomeWidget()
    }
}
