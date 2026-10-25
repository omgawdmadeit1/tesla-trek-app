import ActivityKit
import Foundation

/// Shared Live Activity payload for an in-progress Tr3k.
/// The app and the widget extension both link this module so the attributes
/// type is the same process-to-process.
///
/// `ContentState` stays backward compatible: a Live Activity started by an
/// older build still decodes. New fields are the lock-screen glance line
/// (progress, the next action, and a tone for the rare gold treatment).
@available(iOS 16.1, *)
public struct Tr3kNavigationAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var instruction: String
        public var distanceText: String
        public var etaText: String
        public var stopName: String
        public var progressText: String
        public var action: String
        public var tone: String

        public init(
            instruction: String,
            distanceText: String,
            etaText: String,
            stopName: String,
            progressText: String = "",
            action: String = Tr3kLiveActivityCopy.drive,
            tone: String = "nav"
        ) {
            self.instruction = instruction
            self.distanceText = distanceText
            self.etaText = etaText
            self.stopName = stopName
            self.progressText = progressText
            self.action = action
            self.tone = tone
        }

        private enum CodingKeys: String, CodingKey {
            case instruction
            case distanceText
            case etaText
            case stopName
            case progressText
            case action
            case tone
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            instruction = try container.decodeIfPresent(String.self, forKey: .instruction) ?? ""
            distanceText = try container.decodeIfPresent(String.self, forKey: .distanceText) ?? ""
            etaText = try container.decodeIfPresent(String.self, forKey: .etaText) ?? ""
            stopName = try container.decodeIfPresent(String.self, forKey: .stopName) ?? ""
            progressText = try container.decodeIfPresent(String.self, forKey: .progressText) ?? ""
            action = try container.decodeIfPresent(String.self, forKey: .action) ?? Tr3kLiveActivityCopy.drive
            tone = try container.decodeIfPresent(String.self, forKey: .tone) ?? "nav"
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(instruction, forKey: .instruction)
            try container.encode(distanceText, forKey: .distanceText)
            try container.encode(etaText, forKey: .etaText)
            try container.encode(stopName, forKey: .stopName)
            try container.encode(progressText, forKey: .progressText)
            try container.encode(action, forKey: .action)
            try container.encode(tone, forKey: .tone)
        }
    }

    public var trekName: String
    public var trekId: String
    /// "trek" or "quest". Selects the query key on the tap-through URL.
    public var kind: String

    public init(trekName: String, trekId: String, kind: String = "trek") {
        self.trekName = trekName
        self.trekId = trekId
        self.kind = kind == "quest" ? "quest" : "trek"
    }

    private enum CodingKeys: String, CodingKey {
        case trekName
        case trekId
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trekName = try container.decodeIfPresent(String.self, forKey: .trekName) ?? "Tr3k"
        trekId = try container.decodeIfPresent(String.self, forKey: .trekId) ?? ""
        let decodedKind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "trek"
        kind = decodedKind == "quest" ? "quest" : "trek"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(trekName, forKey: .trekName)
        try container.encode(trekId, forKey: .trekId)
        try container.encode(kind, forKey: .kind)
    }
}

@available(iOS 16.1, *)
public extension Tr3kNavigationAttributes.ContentState {
    static let empty = Tr3kNavigationAttributes.ContentState(
        instruction: "",
        distanceText: "",
        etaText: "",
        stopName: "",
        progressText: "",
        action: Tr3kLiveActivityCopy.drive,
        tone: "nav"
    )
}

/// Lock-screen copy and the tap URL. Kept next to the attributes so the
/// widget extension and the shell agree on the words.
@available(iOS 16.1, *)
public enum Tr3kLiveActivityCopy {
    public static let drive = "Drive"
    public static let park = "Park"
    public static let hunt = "Hunt AR"
    public static let join = "JOIN Live Drop"
    public static let complete = "Complete"
    /// How long a finished Tr3k stays on the lock screen before it is removed.
    public static let endedLinger: TimeInterval = 45

    public struct Identity: Equatable {
        public var id: String
        public var name: String
        public var kind: String

        public init(id: String, name: String, kind: String) {
            self.id = id
            self.name = name
            self.kind = kind == "quest" ? "quest" : "trek"
        }
    }

    public enum Ending {
        case none
        case cancel
        case complete
    }

    public static func text(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            return number.stringValue
        default:
            return nil
        }
    }

    public static func flag(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
            return nil
        case let text as String:
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes":
                return true
            case "0", "false", "no":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    public static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.intValue
        }
        if let text = value as? String, let number = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return number
        }
        return nil
    }

    /// Partial merge. A missing key keeps the previous string. A present key
    /// replaces it, including an empty string when the caller wants the line gone.
    public static func next(
        from previous: Tr3kNavigationAttributes.ContentState,
        fields: [String: Any]
    ) -> Tr3kNavigationAttributes.ContentState {
        var state = previous
        let actionBefore = state.action

        if let phase = text(fields["phase"]) ?? text(fields["status"]) ?? text(fields["state"]) {
            if let mapped = action(forPhase: phase) {
                state.action = mapped
            }
        }

        let instruction = lookup(fields, ["instruction", "step", "maneuver"])
        if instruction.found {
            state.instruction = clip(instruction.value, 140)
        }

        let distance = lookup(fields, ["distanceText", "distance"])
        if distance.found {
            state.distanceText = clip(distance.value, 32)
        }
        let eta = lookup(fields, ["etaText", "eta"])
        if eta.found {
            state.etaText = clip(eta.value, 32)
        }
        let stop = lookup(fields, ["stopName", "stop"])
        if stop.found {
            state.stopName = clip(stop.value, 80)
        }
        if let progress = progress(from: fields) {
            state.progressText = progress
        }

        let explicitAction = lookup(fields, ["action", "nextAction", "next"])
        if explicitAction.found, let canonical = canonicalAction(explicitAction.value) {
            state.action = canonical
        } else if explicitAction.found, explicitAction.value.count <= 24, !explicitAction.value.isEmpty {
            state.action = explicitAction.value
        } else if instruction.found, !explicitAction.found, let inferred = inferredAction(in: instruction.value) {
            state.action = inferred
        }

        let rare = flag(fields["rare"]) == true || isRare(text(fields["rarity"]))
        let drop = flag(fields["liveDrop"]) == true || flag(fields["live"]) == true
        let toneSpecified = lookup(fields, ["tone"]).found || lookup(fields, ["phase", "status", "state"]).found
        if drop {
            state.action = join
            state.tone = "drop"
        } else if state.action != actionBefore || toneSpecified || rare || explicitAction.found {
            state.tone = resolvedTone(action: state.action, rare: rare, explicit: text(fields["tone"]))
        }
        return state
    }

    public static func ending(in fields: [String: Any]) -> Ending {
        if flag(fields["ended"]) == true || flag(fields["complete"]) == true || flag(fields["completed"]) == true {
            return .complete
        }
        if flag(fields["cancel"]) == true || flag(fields["cancelled"]) == true || flag(fields["canceled"]) == true {
            return .cancel
        }
        let keys = ["phase", "status", "state", "action", "nextAction"]
        for key in keys {
            guard let value = text(fields[key])?.lowercased() else { continue }
            switch value {
            case "cancel", "cancelled", "canceled":
                return .cancel
            case "ended", "end", "complete", "completed", "done":
                return .complete
            default:
                continue
            }
        }
        if let instruction = text(fields["instruction"])?.lowercased() {
            if instruction.contains("trek complete") || instruction.contains("quest complete") || instruction.contains("tr3k complete") {
                return .complete
            }
        }
        return .none
    }

    public static func identity(fields: [String: Any], fallback: Identity) -> Identity {
        var next = fallback
        let questId = text(fields["questId"])
        let trekId = text(fields["trekId"])
        let namedKind = text(fields["kind"])?.lowercased()
        if namedKind == "quest" || (questId != nil && trekId == nil) {
            next.kind = "quest"
        } else if namedKind == "trek" {
            next.kind = "trek"
        }
        if let id = next.kind == "quest" ? (questId ?? trekId) : (trekId ?? questId) {
            next.id = clip(id, 128)
            if trekId == nil, questId != nil {
                next.kind = "quest"
            }
        }
        let name = next.kind == "quest"
            ? (text(fields["questName"]) ?? text(fields["trekName"]))
            : (text(fields["trekName"]) ?? text(fields["questName"]))
        if let name {
            next.name = clip(name, 80)
        }
        return next
    }

    public static func progress(index: Int, count: Int) -> String? {
        guard count > 0 else { return nil }
        let shown = index <= 0 ? 1 : min(index, count)
        return "\(shown)/\(count)"
    }

    public static func progress(from fields: [String: Any]) -> String? {
        if let raw = text(fields["progressText"]) ?? text(fields["progress"]) {
            if let parsed = progress(parsing: raw) { return parsed }
            if raw.count <= 12 { return raw }
        }
        let index = int(fields["stopIndex"]) ?? int(fields["currentStop"]) ?? int(fields["stop"])
        let count = int(fields["stopCount"]) ?? int(fields["totalStops"]) ?? int(fields["total"])
        if let index, let count {
            return progress(index: index, count: count)
        }
        return nil
    }

    public static func canonicalAction(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "drive", "nav", "navigate", "go":
            return drive
        case "park", "parked", "arrive", "arrived":
            return park
        case "hunt", "hunt ar", "ar", "huntar":
            return hunt
        case "join", "join live drop", "live drop", "drop", "livedrop":
            return join
        case "complete", "completed", "done", "ended":
            return complete
        default:
            return nil
        }
    }

    public static func inferredAction(in text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("trek complete") || lower.contains("quest complete") || lower.contains("tr3k complete") {
            return complete
        }
        if lower.contains("live drop") || (containsWord(lower, "join") && (lower.contains("space") || lower.contains("chat") || lower.contains("drop"))) {
            return join
        }
        if lower.contains("you've arrived") || lower.contains("you have arrived") || lower.contains("youve arrived") || containsWord(lower, "park") {
            return park
        }
        if lower.contains("look around") || lower.contains("treasure") || containsWord(lower, "hunt") || lower.contains("hunt ar") {
            return hunt
        }
        if containsWord(lower, "turn") || lower.contains("continue") || containsWord(lower, "head") || containsWord(lower, "drive") || spokenDistance(lower) != nil {
            return drive
        }
        return nil
    }

    public static func spokenDistance(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(\d+(?:\.\d+)?)\s*(kilometers|kilometer|meters|meter|miles|mile|feet|foot|km|mi|ft|m)\b"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else { return nil }
        let number = String(text[numberRange])
        let unit = String(text[unitRange]).lowercased()
        let label: String
        switch unit {
        case "kilometers", "kilometer", "km":
            label = "km"
        case "meters", "meter", "m":
            label = "m"
        case "miles", "mile", "mi":
            label = "mi"
        case "feet", "foot", "ft":
            label = "ft"
        default:
            return nil
        }
        return "\(number) \(label)"
    }

    public static func spokenETA(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(\d+)\s*(minutes|minute|mins|min)\b"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let numberRange = Range(match.range(at: 1), in: text) else { return nil }
        return "\(text[numberRange]) min"
    }

    public static func formatMeters(_ meters: Double) -> String {
        guard meters.isFinite, meters >= 0 else { return "" }
        if meters < 40 { return "Here" }
        if meters < 1000 { return "\(Int(meters.rounded())) m" }
        let km = meters / 1000
        if km < 10 {
            return String(format: "%.1f km", km)
        }
        return "\(Int(km.rounded())) km"
    }

    public static func formatETA(meters: Double, speedMps: Double?) -> String {
        guard meters.isFinite, meters >= 40 else { return "" }
        let speed: Double
        if let speedMps, speedMps.isFinite, speedMps > 1.2 {
            speed = speedMps
        } else {
            speed = 11
        }
        let minutes = Int((meters / speed / 60).rounded())
        if minutes <= 1 { return "<1 min" }
        return "\(minutes) min"
    }

    public static func compactTrailing(action: String, distanceText: String) -> String {
        switch action {
        case join:
            return "Drop"
        case hunt:
            return "Hunt"
        case park:
            return "Park"
        case complete:
            return "Done"
        default:
            if !distanceText.isEmpty, distanceText != "Here" { return distanceText }
            return drive
        }
    }

    /// Opens the app on the active Tr3k. Same URL the home screen widget uses.
    public static func playURL(id: String, kind: String) -> URL {
        let root = URL(string: "https://tr3k.app/play/")!
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "active" else { return root }
        var components = URLComponents(url: root, resolvingAgainstBaseURL: false)
        let name = kind == "quest" ? "quest" : "trek"
        components?.queryItems = [URLQueryItem(name: name, value: trimmed)]
        return components?.url ?? root
    }

    public static func clip(_ text: String, _ limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit))
    }

    private static func action(forPhase phase: String) -> String? {
        switch phase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "drive", "nav", "navigate":
            return drive
        case "park", "arrive", "arrived":
            return park
        case "hunt", "ar", "hunt ar":
            return hunt
        case "drop", "live", "livedrop", "live drop":
            return join
        case "ended", "end", "complete", "completed", "done":
            return complete
        default:
            return nil
        }
    }

    private static func resolvedTone(action: String, rare: Bool, explicit: String?) -> String {
        if action == join { return "drop" }
        if let explicit, let tone = canonicalTone(explicit) {
            if tone == "drop" { return "drop" }
            if tone == "rare" || (tone == "arrive" && rare && action == hunt) { return "rare" }
            if tone == "arrive" { return "arrive" }
            return "nav"
        }
        if rare && action == hunt { return "rare" }
        if action == park || action == hunt { return "arrive" }
        return "nav"
    }

    private static func canonicalTone(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "nav", "drive":
            return "nav"
        case "arrive", "arrived", "park", "hunt":
            return "arrive"
        case "drop", "live", "livedrop":
            return "drop"
        case "rare", "legendary", "epic":
            return "rare"
        default:
            return nil
        }
    }

    private static func isRare(_ raw: String?) -> Bool {
        switch raw?.lowercased() {
        case "rare", "epic", "legendary":
            return true
        default:
            return false
        }
    }

    private static func progress(parsing raw: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\s*(?:/|of)\s*(\d+)"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(raw.startIndex..., in: raw)
        guard let match = regex.firstMatch(in: raw, options: [], range: range),
              let leftRange = Range(match.range(at: 1), in: raw),
              let rightRange = Range(match.range(at: 2), in: raw),
              let index = Int(raw[leftRange]),
              let count = Int(raw[rightRange]) else { return nil }
        return progress(index: index, count: count)
    }

    private static func containsWord(_ text: String, _ word: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func lookup(_ fields: [String: Any], _ keys: [String]) -> (found: Bool, value: String) {
        for key in keys {
            guard let raw = fields[key] else { continue }
            if raw is NSNull { return (true, "") }
            return (true, text(raw) ?? "")
        }
        return (false, "")
    }
}
