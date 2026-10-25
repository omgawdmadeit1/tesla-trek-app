import Foundation

/// Slim Tr3k refs shared by the app and the home screen widget.
///
/// The web play page saves `{ key, v, at, nearby, active, lat, lng }`.
/// Nearby and active stay slim: id, place name, lat/lng, category, route
/// order, and game copy. Anything else (raw place records, phone, URL) is
/// dropped before it touches disk.
public enum Tr3kOfflineCache {
    public static let suiteName = "group.app.tr3k.ios"
    public static let defaultKey = "tr3k.offline.v1"
    public static let widgetKind = "app.tr3k.ios.widget.home"

    public static func save(_ raw: [String: Any]) -> [String: Any] {
        let key = normalizeKey(string(raw["key"]))
        let record = sanitizeRecord(raw, key: key)
        if let data = jsonData(record) {
            defaults?.set(data, forKey: storageKey(key))
            if key == defaultKey {
                writeSnapshotFile(data)
            }
        }
        return record
    }

    public static func load(key rawKey: String?) -> [String: Any] {
        let key = normalizeKey(rawKey)
        return loadRecord(key: key) ?? [:]
    }

    public static func clear(key rawKey: String?) -> [String: Any] {
        let key = normalizeKey(rawKey)
        defaults?.removeObject(forKey: storageKey(key))
        if key == defaultKey {
            if let url = snapshotFileURL() {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return ["cleared": true, "key": key]
    }

    public static func snapshot() -> Tr3kWidgetModel {
        guard let record = loadRecord(key: defaultKey) else { return .empty }
        return model(from: record)
    }

    /// Last coordinate the play page or the location bridge stored for the widget.
    public static func lastCoordinate() -> (latitude: Double, longitude: Double)? {
        guard let record = loadRecord(key: defaultKey) else { return nil }
        guard let latitude = coordinate(record["lat"], range: -90...90),
              let longitude = coordinate(record["lng"], range: -180...180) else { return nil }
        return (latitude, longitude)
    }

    /// `always`, `whenInUse`, `denied`, `restricted`, or `prompt`. Separate from the trek record so a web save cannot wipe it.
    public static func noteLocationStatus(_ status: String) {
        let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 32 else { return }
        defaults?.set(trimmed, forKey: locationStatusKey)
    }

    public static func locationStatus() -> String? {
        guard let status = defaults?.string(forKey: locationStatusKey) else { return nil }
        let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Updates lat/lng on the default record without dropping nearby or the active Tr3k.
    public static func noteCoordinate(latitude: Double, longitude: Double) {
        guard coordinate(latitude, range: -90...90) != nil,
              coordinate(longitude, range: -180...180) != nil else { return }
        var raw = load(key: defaultKey)
        if raw.isEmpty {
            raw["nearby"] = [Any]()
            raw["active"] = NSNull()
        }
        raw["key"] = defaultKey
        raw["lat"] = latitude
        raw["lng"] = longitude
        _ = save(raw)
    }

    /// Merges an `/api/nearby` pool into the default record.
    ///
    /// Ids the play page already saved keep their themed `title`. A short new
    /// list is ignored so a partial response cannot wipe a good snapshot.
    public static func replaceNearby(_ pool: [[String: Any]], latitude: Double, longitude: Double) -> Tr3kWidgetModel {
        guard coordinate(latitude, range: -90...90) != nil,
              coordinate(longitude, range: -180...180) != nil else { return snapshot() }
        let record = loadRecord(key: defaultKey) ?? [:]
        let previous = sanitizeList(record["nearby"])
        let poolIds = Set(pool.compactMap { string($0["id"]) })
        var kept: [[String: Any]] = []
        var seen = Set<String>()
        for item in previous {
            guard let id = string(item["id"]), poolIds.contains(id), seen.insert(id).inserted else { continue }
            kept.append(item)
            if kept.count == 12 { break }
        }
        if kept.count < 2 {
            guard pool.count >= 4 || previous.isEmpty else { return snapshot() }
            for item in roundRobin(pool, limit: 6) {
                guard let slim = sanitizeRef(item), let id = string(slim["id"]), seen.insert(id).inserted else { continue }
                kept.append(slim)
                if kept.count == 6 { break }
            }
        }
        guard !kept.isEmpty else { return snapshot() }
        kept = kept.enumerated().map { index, item in
            var copy = item
            copy["order"] = index
            return copy
        }
        var raw: [String: Any] = [
            "key": defaultKey,
            "v": intValue(record["v"]) ?? 1,
            "at": Date().timeIntervalSince1970 * 1000,
            "nearby": kept,
            "lat": latitude,
            "lng": longitude
        ]
        if let active = record["active"], !(active is NSNull) {
            raw["active"] = active
        }
        _ = save(raw)
        return snapshot()
    }

    // MARK: - Record

    private static func sanitizeRecord(_ raw: [String: Any], key: String) -> [String: Any] {
        var record: [String: Any] = [
            "key": key,
            "v": intValue(raw["v"]) ?? 1,
            "at": finite(raw["at"]) ?? Date().timeIntervalSince1970 * 1000,
            "nearby": sanitizeList(raw["nearby"])
        ]
        if let active = sanitizeRef(raw["active"]) {
            record["active"] = active
        } else {
            record["active"] = NSNull()
        }
        if let lat = coordinate(raw["lat"], range: -90...90) {
            record["lat"] = lat
        }
        if let lng = coordinate(raw["lng"], range: -180...180) {
            record["lng"] = lng
        }
        return record
    }

    private static func sanitizeList(_ value: Any?) -> [[String: Any]] {
        let items: [Any]
        if let list = value as? [Any] {
            items = list
        } else if let list = value as? [[String: Any]] {
            items = list.map { $0 as Any }
        } else if let list = value as? NSArray {
            items = list.map { $0 }
        } else {
            items = []
        }
        var slim: [[String: Any]] = []
        var seen = Set<String>()
        for item in items {
            guard let ref = sanitizeRef(item) else { continue }
            let id = string(ref["id"]) ?? ""
            guard seen.insert(id).inserted else { continue }
            slim.append(ref)
            if slim.count == 24 { break }
        }
        return slim
    }

    /// Keeps the web's own slim keys and fills `id`, `name`, and `kind` when
    /// those arrived under an alias (`placeName`, `routeOrder`, `gameCopy`).
    static func sanitizeRef(_ value: Any?) -> [String: Any]? {
        let raw = dictionary(value)
        guard var slim = copiedScalars(raw) else { return nil }
        guard let id = firstString(slim, keys: ["id", "trekId", "questId"]) else { return nil }
        slim["id"] = clip(id, 128)
        if slim["name"] == nil, let name = firstString(slim, keys: ["placeName", "place", "title"]) {
            slim["name"] = name
        }
        if slim["order"] == nil, let order = firstInt(slim, keys: ["routeOrder"]) {
            slim["order"] = order
        }
        if slim["copy"] == nil, let copy = firstString(slim, keys: ["gameCopy"]) {
            slim["copy"] = copy
        }
        if let lat = coordinate(firstRaw(slim, keys: ["lat", "latitude"]), range: -90...90) {
            slim["lat"] = lat
        } else {
            slim.removeValue(forKey: "lat")
            slim.removeValue(forKey: "latitude")
        }
        if let lng = coordinate(firstRaw(slim, keys: ["lng", "lon", "longitude"]), range: -180...180) {
            slim["lng"] = lng
        } else {
            slim.removeValue(forKey: "lng")
            slim.removeValue(forKey: "lon")
            slim.removeValue(forKey: "longitude")
        }
        slim["kind"] = inferKind(slim)
        return slim
    }

    private static let allowedKeys: Set<String> = [
        "id", "trekId", "questId", "name", "placeName", "place", "title",
        "lat", "lng", "latitude", "longitude", "lon",
        "category", "order", "routeOrder", "copy", "gameCopy", "kind", "type"
    ]

    private static func copiedScalars(_ raw: [String: Any]?) -> [String: Any]? {
        guard let raw else { return nil }
        var slim: [String: Any] = [:]
        for key in allowedKeys {
            guard let value = raw[key] else { continue }
            let limit = (key == "copy" || key == "gameCopy") ? 500 : 160
            guard let scalar = scalar(value, limit: limit) else { continue }
            slim[key] = scalar
        }
        return slim.isEmpty ? nil : slim
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] { return dict }
        if let id = value as? String {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : ["id": trimmed]
        }
        if let number = value as? NSNumber, !isBoolean(number) {
            return ["id": number.stringValue]
        }
        if let list = value as? [Any], let first = list.first {
            return dictionary(first)
        }
        return nil
    }

    private static func inferKind(_ raw: [String: Any]) -> String {
        let named = (firstString(raw, keys: ["kind", "type"]) ?? "").lowercased()
        if named == "quest" { return "quest" }
        if let flag = raw["quest"] as? Bool, flag { return "quest" }
        if firstString(raw, keys: ["questId"]) != nil && firstString(raw, keys: ["id", "trekId"]) == nil {
            return "quest"
        }
        return "trek"
    }

    // MARK: - Widget model

    private static func model(from record: [String: Any]) -> Tr3kWidgetModel {
        let nearby = places(record["nearby"])
        let active = place(record["active"])
        return Tr3kWidgetModel(active: active, nearby: nearby, primaryLink: primaryLink(active: active, nearby: nearby))
    }

    private static func places(_ value: Any?) -> [Tr3kPlaceRef] {
        let items: [Any]
        if let list = value as? [Any] {
            items = list
        } else if let list = value as? [[String: Any]] {
            items = list.map { $0 as Any }
        } else if let list = value as? NSArray {
            items = list.map { $0 }
        } else {
            items = []
        }
        var refs: [Tr3kPlaceRef] = []
        var seen = Set<String>()
        for (offset, item) in items.enumerated() {
            guard let ref = place(item, tieBreak: offset), seen.insert(ref.id).inserted else { continue }
            refs.append(ref)
        }
        return refs.enumerated().sorted { lhs, rhs in
            switch (lhs.element.order, rhs.element.order) {
            case let (left?, right?) where left != right:
                return left < right
            default:
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    private static func place(_ value: Any?, tieBreak: Int = 0) -> Tr3kPlaceRef? {
        guard let raw = sanitizeRef(value), let id = string(raw["id"]) else { return nil }
        let kind = string(raw["kind"]) ?? "trek"
        let title = string(raw["title"])
        let placeName = firstString(raw, keys: ["name", "placeName", "place"])
        let place = (title != nil && placeName != nil && placeName != title) ? placeName : nil
        return Tr3kPlaceRef(
            id: id,
            name: title ?? placeName ?? "Tr3k",
            place: place,
            kind: kind,
            category: string(raw["category"]),
            order: firstInt(raw, keys: ["order", "routeOrder"]),
            gameCopy: firstString(raw, keys: ["copy", "gameCopy"]),
            link: Tr3kLinks.open(id: id, kind: kind),
            tieBreak: tieBreak
        )
    }

    /// One nearby Tr3k opens that Tr3k. Several open the play list. An active Tr3k is the link only when nothing nearby is saved.
    private static func primaryLink(active: Tr3kPlaceRef?, nearby: [Tr3kPlaceRef]) -> URL {
        if nearby.isEmpty, let active { return active.link }
        if nearby.count == 1, active == nil, let only = nearby.first { return only.link }
        return Tr3kLinks.play
    }

    /// Nearest of each category, then the next nearest, so a cold list is not six parks.
    private static func roundRobin(_ pool: [[String: Any]], limit: Int) -> [[String: Any]] {
        var buckets: [String: [[String: Any]]] = [:]
        var order: [String] = []
        for item in pool {
            let key = string(item["category"]) ?? "Tr3k"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        var picked: [[String: Any]] = []
        var round = 0
        while picked.count < limit {
            var added = false
            for key in order {
                guard let bucket = buckets[key], round < bucket.count else { continue }
                picked.append(bucket[round])
                added = true
                if picked.count == limit { break }
            }
            if !added { break }
            round += 1
        }
        return picked
    }

    // MARK: - Disk

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static func storageKey(_ key: String) -> String {
        "cache.\(key)"
    }

    private static let locationStatusKey = "widget.location.status"

    private static func snapshotFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
            .appendingPathComponent("tr3k-offline-v1.json", isDirectory: false)
    }

    private static func writeSnapshotFile(_ data: Data) {
        guard let url = snapshotFileURL() else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func loadRecord(key: String) -> [String: Any]? {
        let stored = readDefaults(key)
        let file = key == defaultKey ? readSnapshotFile() : nil
        switch (stored, file) {
        case let (left?, right?):
            return timestamp(left) >= timestamp(right) ? left : right
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        default:
            return nil
        }
    }

    private static func readDefaults(_ key: String) -> [String: Any]? {
        guard let data = defaults?.data(forKey: storageKey(key)) else { return nil }
        return jsonObject(data)
    }

    private static func readSnapshotFile() -> [String: Any]? {
        guard let url = snapshotFileURL(), let data = try? Data(contentsOf: url) else { return nil }
        return jsonObject(data)
    }

    private static func jsonData(_ object: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [])
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
    }

    private static func timestamp(_ record: [String: Any]) -> Double {
        finite(record["at"]) ?? 0
    }

    // MARK: - Scalars

    static func normalizeKey(_ key: String?) -> String {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return defaultKey }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return defaultKey }
        return trimmed
    }

    private static func scalar(_ value: Any, limit: Int) -> Any? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return clip(trimmed, limit)
        }
        if let number = value as? NSNumber {
            guard !isBoolean(number) else { return nil }
            let double = number.doubleValue
            guard double.isFinite else { return nil }
            if double.rounded() == double, abs(double) < Double(Int.max) {
                return Int(double)
            }
            return double
        }
        return nil
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func firstRaw(_ raw: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = raw[key] { return value }
        }
        return nil
    }

    private static func firstString(_ raw: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = string(raw[key]) { return value }
        }
        return nil
    }

    private static func firstInt(_ raw: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = intValue(raw[key]) { return value }
        }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber, !isBoolean(number) {
            return number.intValue
        }
        if let text = value as? String, let number = Int(text) {
            return number
        }
        return nil
    }

    private static func finite(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, !isBoolean(number) {
            let double = number.doubleValue
            return double.isFinite ? double : nil
        }
        if let text = value as? String, let double = Double(text), double.isFinite {
            return double
        }
        return nil
    }

    private static func coordinate(_ value: Any?, range: ClosedRange<Double>) -> Double? {
        guard let double = finite(value), range.contains(double) else { return nil }
        return double
    }

    private static func clip(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }
}

public struct Tr3kPlaceRef: Identifiable, Equatable {
    public let id: String
    public let name: String
    /// Map place when `name` is the themed title.
    public let place: String?
    public let kind: String
    public let category: String?
    public let order: Int?
    public let gameCopy: String?
    public let link: URL
    let tieBreak: Int
}

public struct Tr3kWidgetModel: Equatable {
    public let active: Tr3kPlaceRef?
    public let nearby: [Tr3kPlaceRef]
    public let primaryLink: URL
    /// True when the widget has nothing nearby to show until location is on.
    public let needsLocation: Bool

    public var isEmpty: Bool { active == nil && nearby.isEmpty }

    public init(active: Tr3kPlaceRef?, nearby: [Tr3kPlaceRef], primaryLink: URL, needsLocation: Bool = false) {
        self.active = active
        self.nearby = nearby
        self.primaryLink = primaryLink
        self.needsLocation = needsLocation
    }

    /// Hides stale nearby rows. The saved record is left alone.
    public func withholdingNearby() -> Tr3kWidgetModel {
        Tr3kWidgetModel(
            active: active,
            nearby: [],
            primaryLink: active?.link ?? Tr3kLinks.play,
            needsLocation: true
        )
    }

    /// Snapshot gate that does not touch Core Location. The timeline applies the live status.
    public func gatedForSnapshot() -> Tr3kWidgetModel {
        let stored = Tr3kOfflineCache.locationStatus()
        if stored == "denied" || stored == "restricted" {
            return withholdingNearby()
        }
        return self
    }

    public static let empty = Tr3kWidgetModel(active: nil, nearby: [], primaryLink: Tr3kLinks.play, needsLocation: true)

    public static let placeholder = Tr3kWidgetModel(
        active: nil,
        nearby: [
            Tr3kPlaceRef(
                id: "sunset",
                name: "Sunset Glow Walk",
                place: "Bogan Park",
                kind: "trek",
                category: "Park",
                order: 0,
                gameCopy: nil,
                link: Tr3kLinks.play,
                tieBreak: 0
            ),
            Tr3kPlaceRef(
                id: "after-dark",
                name: "After Dark Statue Check",
                place: nil,
                kind: "trek",
                category: "Monument",
                order: 1,
                gameCopy: nil,
                link: Tr3kLinks.play,
                tieBreak: 1
            ),
            Tr3kPlaceRef(
                id: "grass",
                name: "Touch Grass Grove Run",
                place: nil,
                kind: "trek",
                category: "Park",
                order: 2,
                gameCopy: nil,
                link: Tr3kLinks.play,
                tieBreak: 2
            )
        ],
        primaryLink: Tr3kLinks.play
    )
}

public enum Tr3kLinks {
    public static let play = URL(string: "https://tr3k.app/play/")!

    public static func open(id: String, kind: String) -> URL {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return play }
        var components = URLComponents(string: "https://tr3k.app/play/")
        let name = kind == "quest" ? "quest" : "trek"
        components?.queryItems = [URLQueryItem(name: name, value: trimmed)]
        return components?.url ?? play
    }
}
