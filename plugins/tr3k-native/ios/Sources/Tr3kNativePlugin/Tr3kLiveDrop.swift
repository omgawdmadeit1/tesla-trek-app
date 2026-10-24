import Foundation
import UIKit

/// X Live Drop: a Space or group Chat unlocked when a Tr3k stop geofence fires.
///
/// The saved record is ids, a url, an optional name, and an optional radius.
/// There is no X token and no chat server. `open` prefers the installed X app
/// (`x://`, then `twitter://`) and falls back to `https://x.com/...`.
enum Tr3kLiveDropKind: String {
    case space
    case chat

    init(_ raw: String?) {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = value == "chat" ? .chat : .space
    }

    var joinLabel: String {
        switch self {
        case .space:
            return "JOIN 𝕏 SPACE"
        case .chat:
            return "JOIN 𝕏 CHAT"
        }
    }

    var demoURL: String {
        switch self {
        case .space:
            return "https://x.com/i/spaces"
        case .chat:
            return "https://x.com/messages"
        }
    }
}

enum Tr3kLiveDropCopy {
    static let note = "Only people at this stop."

    static func headline(title: String?) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return "LIVE" }
        if trimmed.count <= 16 {
            return trimmed.uppercased(with: Locale(identifier: "en_US_POSIX"))
        }
        return trimmed
    }
}

struct Tr3kLiveDrop: Equatable {
    var stopId: String
    var kind: Tr3kLiveDropKind
    var url: String
    var title: String?
    var unlockRadiusM: Double?
    var demo: Bool

    var type: String { kind.rawValue }

    func storedFields() -> [String: Any] {
        var fields: [String: Any] = [
            "stopId": stopId,
            "type": type,
            "url": url,
            "demo": demo
        ]
        if let title, !title.isEmpty { fields["title"] = title }
        if let unlockRadiusM { fields["unlockRadiusM"] = unlockRadiusM }
        return fields
    }

    func queryFields() -> [String: Any] {
        var fields = storedFields()
        fields["found"] = true
        return fields
    }

    func eventFields(source: String, unlockId: String, issuedAt: Double) -> [String: Any] {
        var fields = queryFields()
        fields["source"] = source
        fields["unlockId"] = unlockId
        fields["issuedAt"] = issuedAt
        return fields
    }
}

struct Tr3kXOpenResult {
    var opened: Bool
    var url: String?
    var via: String?
    var reason: String?
}

/// Turns a Space or Chat link into an ordered list of X app URLs.
enum Tr3kXLink {
    private static let hosts: Set<String> = [
        "x.com", "www.x.com", "mobile.x.com",
        "twitter.com", "www.twitter.com", "mobile.twitter.com"
    ]

    static func candidates(for raw: String) -> [URL] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 500,
              !trimmed.contains(where: \.isNewline),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["https", "http", "x", "twitter"].contains(scheme) else {
            return []
        }
        if scheme == "http" || scheme == "https" {
            guard let host = url.host?.lowercased(), hosts.contains(host) else { return [] }
        }

        var ordered: [URL] = []
        func push(_ string: String) {
            guard let next = URL(string: string) else { return }
            if ordered.contains(where: { $0.absoluteString == next.absoluteString }) { return }
            ordered.append(next)
        }

        switch spaceMatch(url) {
        case .id(let spaceId):
            push("x://spaces/\(spaceId)")
            push("twitter://spaces/\(spaceId)")
            push("https://x.com/i/spaces/\(spaceId)")
            return ordered
        case .home:
            push("x://spaces")
            push("twitter://spaces")
            push("https://x.com/i/spaces")
            return ordered
        case .passthrough:
            if scheme == "x" || scheme == "twitter" { push(url.absoluteString) }
            push(httpsX(url))
            return ordered
        case nil:
            break
        }
        if let chat = chatTarget(url) {
            if let id = chat.id {
                push("x://messages/\(id)")
                push("twitter://messages/\(id)")
                if chat.channel == "chat" {
                    push("x://chat/\(id)")
                    push("twitter://chat/\(id)")
                    push("https://x.com/i/chat/\(id)")
                }
                push("https://x.com/messages/\(id)")
            } else if chat.channel == "chat" {
                push("x://messages")
                push("twitter://messages")
                push("https://x.com/i/chat")
            } else {
                push("x://messages")
                push("twitter://messages")
                push("https://x.com/messages")
            }
            if scheme == "http" || scheme == "https" { push(httpsX(url)) }
            if scheme == "x" || scheme == "twitter" { push(url.absoluteString) }
            return ordered
        }

        if scheme == "x" || scheme == "twitter" {
            push(url.absoluteString)
            push(httpsFallback(url))
            return ordered
        }
        push(rewriteApp(url, scheme: "x"))
        push(rewriteApp(url, scheme: "twitter"))
        push(httpsX(url))
        return ordered
    }

    /// Prefer the native X app. `canOpenURL` needs `twitter` and `x` in
    /// `LSApplicationQueriesSchemes`. https stays available when the app is missing.
    static func open(_ raw: String, completion: @escaping (Tr3kXOpenResult) -> Void) {
        let list = candidates(for: raw)
        DispatchQueue.main.async {
            guard !list.isEmpty else {
                completion(Tr3kXOpenResult(opened: false, url: nil, via: nil, reason: "invalid"))
                return
            }
            func attempt(_ index: Int) {
                if index >= list.count {
                    completion(Tr3kXOpenResult(opened: false, url: nil, via: nil, reason: "unavailable"))
                    return
                }
                let url = list[index]
                let scheme = url.scheme?.lowercased() ?? ""
                if scheme == "x" || scheme == "twitter" {
                    guard UIApplication.shared.canOpenURL(url) else {
                        attempt(index + 1)
                        return
                    }
                }
                UIApplication.shared.open(url, options: [:]) { success in
                    DispatchQueue.main.async {
                        if success {
                            let via = (scheme == "http" || scheme == "https") ? "https" : scheme
                            completion(Tr3kXOpenResult(opened: true, url: url.absoluteString, via: via, reason: nil))
                        } else {
                            attempt(index + 1)
                        }
                    }
                }
            }
            attempt(0)
        }
    }

    private enum SpaceMatch {
        case id(String)
        case home
        case passthrough
    }

    /// A segment after `spaces` that is not a clean id is left on the caller's
    /// https link instead of being rewritten to the Spaces home.
    private static func spaceMatch(_ url: URL) -> SpaceMatch? {
        let host = url.host?.lowercased() ?? ""
        let parts = pathParts(url)
        let raw: String?
        if host == "spaces" {
            raw = parts.first ?? queryValue(url, name: "id")
            if raw == nil { return .home }
        } else if parts.contains("spaces") {
            raw = idAfter("spaces", parts: parts)
            if raw == nil { return .home }
        } else {
            return nil
        }
        if let raw, let id = cleanId(raw) { return .id(id) }
        return raw == nil ? .home : .passthrough
    }

    private struct ChatTarget {
        var id: String?
        var channel: String
    }

    private static func chatTarget(_ url: URL) -> ChatTarget? {
        let host = url.host?.lowercased() ?? ""
        let parts = pathParts(url)
        if host == "messages" || parts.contains("messages") {
            let raw = host == "messages" ? parts.first : idAfter("messages", parts: parts)
            if let raw, cleanId(raw) == nil { return nil }
            let id = cleanId(raw) ?? cleanId(queryValue(url, name: "id"))
            return ChatTarget(id: id, channel: "messages")
        }
        if host == "chat" || parts.contains("chat") {
            let raw = host == "chat" ? parts.first : idAfter("chat", parts: parts)
            if let raw, cleanId(raw) == nil { return nil }
            let id = cleanId(raw) ?? cleanId(queryValue(url, name: "id"))
            return ChatTarget(id: id, channel: "chat")
        }
        return nil
    }

    private static func pathParts(_ url: URL) -> [String] {
        url.path.split(separator: "/").map(String.init)
    }

    private static func idAfter(_ name: String, parts: [String]) -> String? {
        guard let index = parts.firstIndex(of: name), index + 1 < parts.count else { return nil }
        return parts[index + 1]
    }

    private static func queryValue(_ url: URL, name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    private static func cleanId(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard (1...80).contains(trimmed.count) else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return trimmed
    }

    private static func httpsX(_ url: URL) -> String {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.scheme = "https"
        parts?.host = "x.com"
        return parts?.string ?? "https://x.com"
    }

    private static func httpsFallback(_ url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        let path = url.path
        if host.isEmpty { return "https://x.com" }
        if path.isEmpty || path == "/" { return "https://x.com/\(host)" }
        let suffix = path.hasPrefix("/") ? path : "/\(path)"
        return "https://x.com/\(host)\(suffix)"
    }

    private static func rewriteApp(_ url: URL, scheme: String) -> String {
        let parts = pathParts(url)
        guard let first = parts.first else { return "\(scheme)://" }
        let rest = parts.dropFirst().joined(separator: "/")
        if rest.isEmpty { return "\(scheme)://\(first)" }
        return "\(scheme)://\(first)/\(rest)"
    }
}

/// In-memory plus UserDefaults. Main thread only. Not the App Group.
final class Tr3kLiveDropStore {
    static let shared = Tr3kLiveDropStore()
    private static let storageKey = "tr3k.livedrop.v1"
    private static let maxDrops = 20
    private var cached: [Tr3kLiveDrop]?

    private init() {}

    func save(_ raw: [String: Any], allowMissingURL: Bool = false) -> Tr3kLiveDrop? {
        guard let drop = Self.parse(raw, allowMissingURL: allowMissingURL) else { return nil }
        var next = all()
        if let index = next.firstIndex(where: { $0.stopId == drop.stopId }) {
            next[index] = drop
        } else {
            next.append(drop)
        }
        if next.count > Self.maxDrops {
            next.removeFirst(next.count - Self.maxDrops)
        }
        persist(next)
        return drop
    }

    func replace(_ items: [[String: Any]], replaceAll: Bool) -> [Tr3kLiveDrop] {
        var next = replaceAll ? [] : all()
        for item in items {
            guard let drop = Self.parse(item, allowMissingURL: false) else { continue }
            if let index = next.firstIndex(where: { $0.stopId == drop.stopId }) {
                next[index] = drop
            } else {
                next.append(drop)
            }
        }
        if next.count > Self.maxDrops {
            next = Array(next.suffix(Self.maxDrops))
        }
        persist(next)
        return next
    }

    func drop(for stopId: String) -> Tr3kLiveDrop? {
        guard let id = Self.cleanStopId(stopId) else { return nil }
        return all().first(where: { $0.stopId == id })
    }

    func all() -> [Tr3kLiveDrop] {
        if let cached { return cached }
        let loaded = load()
        cached = loaded
        return loaded
    }

    @discardableResult
    func clear(stopId: String?) -> Int {
        let current = all()
        let next: [Tr3kLiveDrop]
        if let stopId, let id = Self.cleanStopId(stopId) {
            next = current.filter { $0.stopId != id }
        } else if stopId != nil {
            return 0
        } else {
            next = []
        }
        let removed = current.count - next.count
        persist(next)
        return removed
    }

    static func parse(_ raw: [String: Any], allowMissingURL: Bool) -> Tr3kLiveDrop? {
        guard let stopId = cleanStopId(raw["stopId"]) else { return nil }
        let kind = Tr3kLiveDropKind(raw["type"] as? String)
        let provided = ((raw["url"] as? String) ?? (raw["deepLink"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitDemo = bool(raw["demo"])
        let url: String
        let demo: Bool
        if provided.isEmpty {
            guard allowMissingURL else { return nil }
            url = kind.demoURL
            demo = true
        } else {
            guard !Tr3kXLink.candidates(for: provided).isEmpty else { return nil }
            url = provided
            demo = explicitDemo ?? false
        }
        return Tr3kLiveDrop(
            stopId: stopId,
            kind: kind,
            url: url,
            title: cleanTitle(raw["title"]),
            unlockRadiusM: radius(raw["unlockRadiusM"]),
            demo: demo
        )
    }

    static func dictionary(_ value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] { return dict }
        guard let dict = value as? NSDictionary else { return nil }
        var out: [String: Any] = [:]
        for (key, val) in dict {
            guard let key = key as? String else { continue }
            out[key] = val
        }
        return out.isEmpty ? nil : out
    }

    static func cleanStopId(_ value: Any?) -> String? {
        let raw: String?
        switch value {
        case let string as String:
            raw = string
        case let number as NSNumber:
            raw = number.stringValue
        default:
            raw = nil
        }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              (1...128).contains(trimmed.count) else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return trimmed
    }

    private static func cleanTitle(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= 80 { return collapsed }
        return String(collapsed.prefix(80))
    }

    private static func radius(_ value: Any?) -> Double? {
        guard let number = number(value), number.isFinite else { return nil }
        return min(500, max(15, number))
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

    private static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let flag as Bool: return flag
        case let number as NSNumber: return number.boolValue
        case let string as String where string == "true": return true
        case let string as String where string == "false": return false
        default: return nil
        }
    }

    private func load() -> [Tr3kLiveDrop] {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return rows.compactMap { Self.parse($0, allowMissingURL: false) }
    }

    private func persist(_ drops: [Tr3kLiveDrop]) {
        cached = drops
        let rows = drops.map { $0.storedFields() }
        guard let data = try? JSONSerialization.data(withJSONObject: rows) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

/// `tr3k://live-drop` and `?liveDrop=1` (or a Space/Chat URL) preview the moment.
enum Tr3kLiveDropLink {
    static func drop(from url: URL) -> Tr3kLiveDrop? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        let host = url.host?.lowercased() ?? ""
        let parts = url.path.split(separator: "/").map(String.init)
        let query = queryItems(url)
        let dedicated = (scheme == "tr3k" && (host == "live-drop" || host == "livedrop"))
            || parts.contains("live-drop")
        let flag = query["liveDrop"]
        guard dedicated || (flag?.isEmpty == false) else { return nil }

        var raw: [String: Any] = [
            "stopId": query["stopId"] ?? "demo"
        ]
        let type = query["liveDropType"] ?? (dedicated ? query["type"] : nil)
        raw["type"] = type ?? "space"
        if let link = query["url"] ?? query["deepLink"], !link.isEmpty {
            raw["url"] = link
        } else if let flag, flag.contains("://") {
            raw["url"] = flag
        }
        if let title = query["liveDropTitle"] ?? (dedicated ? query["title"] : nil) {
            raw["title"] = title
        }
        return Tr3kLiveDropStore.parse(raw, allowMissingURL: true)
    }

    private static func queryItems(_ url: URL) -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return [:]
        }
        var query: [String: String] = [:]
        for item in items {
            guard let value = item.value, !value.isEmpty else { continue }
            query[item.name] = value
        }
        return query
    }
}
