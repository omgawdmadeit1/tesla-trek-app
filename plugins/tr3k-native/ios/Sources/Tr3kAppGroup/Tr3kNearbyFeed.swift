import Foundation

/// The play page's nearby request: `GET /api/nearby?lat&lng&r=12000&v=0`.
///
/// Apple items (`source: "apple"`) and an OSM Overpass `elements` payload both
/// parse. HTML (a challenge page, a 500) becomes an empty pool so the widget
/// keeps the last snapshot.
public enum Tr3kNearbyFeed {
    public static let radiusMeters = 12_000.0
    private static let endpoint = URL(string: "https://tr3k.app/api/nearby")!

    public static func request(latitude: Double, longitude: Double) -> URLRequest? {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "lat", value: decimal(latitude)),
            URLQueryItem(name: "lng", value: decimal(longitude)),
            URLQueryItem(name: "r", value: "12000"),
            URLQueryItem(name: "v", value: "0")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        return request
    }

    /// Up to 40 slim refs, nearest first. The widget merge keeps themed titles for ids in this pool.
    public static func parse(_ data: Data, latitude: Double, longitude: Double) -> [[String: Any]] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let items = dictionaries(json["items"])
        let elements = dictionaries(json["elements"])
        let source = (json["source"] as? String)?.lowercased()
        var candidates: [Candidate] = []
        if !items.isEmpty, source == "apple" || source == nil || elements.isEmpty {
            for item in items {
                if let candidate = apple(item, originLat: latitude, originLng: longitude) {
                    candidates.append(candidate)
                }
            }
        }
        if candidates.isEmpty {
            for element in elements {
                if let candidate = osm(element, originLat: latitude, originLng: longitude) {
                    candidates.append(candidate)
                }
            }
        }
        candidates.sort { $0.meters < $1.meters }
        var seen = Set<String>()
        var pool: [[String: Any]] = []
        for (index, candidate) in candidates.enumerated() {
            guard seen.insert(candidate.id).inserted else { continue }
            pool.append([
                "id": candidate.id,
                "name": candidate.name,
                "lat": candidate.latitude,
                "lng": candidate.longitude,
                "category": candidate.category,
                "kind": "trek",
                "order": index
            ])
            if pool.count == 200 { break }
        }
        return pool
    }

    private struct Candidate {
        var id: String
        var name: String
        var latitude: Double
        var longitude: Double
        var category: String
        var meters: Double
    }

    private static func apple(_ item: [String: Any], originLat: Double, originLng: Double) -> Candidate? {
        guard let id = text(item["id"]), let name = text(item["name"]), !rejected(name) else { return nil }
        guard let latitude = number(item["lat"]), let longitude = number(item["lng"]) else { return nil }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let meters = number(item["d"]) ?? haversine(fromLat: originLat, fromLng: originLng, toLat: latitude, toLng: longitude)
        guard meters >= 0, meters <= radiusMeters else { return nil }
        let category = text(item["w"]) ?? text(item["category"]) ?? "Tr3k"
        return Candidate(id: id, name: clip(name), latitude: latitude, longitude: longitude, category: clip(category), meters: meters)
    }

    private static func osm(_ element: [String: Any], originLat: Double, originLng: Double) -> Candidate? {
        guard let tags = dictionary(element["tags"]), let name = text(tags["name"]), !rejected(name) else { return nil }
        let latitude = number(element["lat"]) ?? number(dictionary(element["center"])?["lat"])
        let longitude = number(element["lon"]) ?? number(element["lng"]) ?? number(dictionary(element["center"])?["lon"])
        guard let latitude, let longitude, (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let meters = haversine(fromLat: originLat, fromLng: originLng, toLat: latitude, toLng: longitude)
        guard meters >= 300, meters <= radiusMeters else { return nil }
        let type = text(element["type"]) ?? "node"
        let prefix = type.first.map(String.init) ?? "n"
        guard let rawId = text(element["id"]) else { return nil }
        let category = text(tags["tourism"]) ?? text(tags["leisure"]) ?? text(tags["historic"]) ?? "Tr3k"
        return Candidate(
            id: "osm-\(prefix)\(rawId)",
            name: clip(name),
            latitude: latitude,
            longitude: longitude,
            category: clip(category),
            meters: meters
        )
    }

    private static func rejected(_ name: String) -> Bool {
        let lower = name.lowercased()
        if name.count < 2 || name.count > 80 { return true }
        return lower.contains("school") || lower.contains("cemetery") || lower.contains("grave")
    }

    private static func dictionaries(_ value: Any?) -> [[String: Any]] {
        if let list = value as? [[String: Any]] { return list }
        guard let list = value as? [Any] else { return [] }
        return list.compactMap { dictionary($0) }
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] { return dict }
        if let dict = value as? NSDictionary, let bridged = dict as? [String: Any] { return bridged }
        return nil
    }

    private static func text(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return number.stringValue
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let double = number.doubleValue
            return double.isFinite ? double : nil
        }
        if let text = value as? String, let double = Double(text), double.isFinite {
            return double
        }
        return nil
    }

    private static func haversine(fromLat: Double, fromLng: Double, toLat: Double, toLng: Double) -> Double {
        let radius = 6_371_000.0
        let phi1 = fromLat * .pi / 180
        let phi2 = toLat * .pi / 180
        let deltaPhi = (toLat - fromLat) * .pi / 180
        let deltaLambda = (toLng - fromLng) * .pi / 180
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return 2 * radius * asin(min(1, sqrt(a)))
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private static func clip(_ text: String) -> String {
        guard text.count > 160 else { return text }
        return String(text.prefix(160))
    }
}
