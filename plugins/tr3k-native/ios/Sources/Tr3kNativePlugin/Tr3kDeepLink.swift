import Foundation

/// Parses Tr3k universal links and the `tr3k` custom scheme.
///
/// Canonical share URL: `https://tr3k.app/play/?trek=<id>`
/// Short path: `https://tr3k.app/t/<id>` and `https://tr3k.app/q/<id>`
/// The custom scheme mirrors that path: `tr3k://t/<id>`, `tr3k://play/?trek=<id>`.
enum Tr3kDeepLink {
    static func url(from notification: Notification) -> URL? {
        if let info = notification.userInfo, let found = url(from: info["url"]) {
            return found
        }
        if let object = notification.object as? [String: Any], let found = url(from: object["url"]) {
            return found
        }
        if let object = notification.object as? [AnyHashable: Any], let found = url(from: object["url"]) {
            return found
        }
        if let object = notification.object as? [String: Any?] {
            let value = object["url"] ?? nil
            if let found = url(from: value) { return found }
        }
        return url(from: notification.object)
    }

    static func payload(for url: URL, issuedAt: TimeInterval) -> [String: Any]? {
        guard let parts = parts(for: url) else { return nil }
        var payload: [String: Any] = [
            "url": url.absoluteString,
            "path": parts.path,
            "query": parts.query,
            "issuedAt": issuedAt
        ]
        if let trekId = parts.trekId { payload["trekId"] = trekId }
        if let questId = parts.questId { payload["questId"] = questId }
        return payload
    }

    private struct Parts {
        var path: String
        var query: [String: String]
        var trekId: String?
        var questId: String?
    }

    private static func parts(for url: URL) -> Parts? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        let host = url.host?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            guard host == "tr3k.app" || host == "www.tr3k.app" else { return nil }
        } else if scheme == "tr3k" {
            // Capacitor's local origin uses this scheme with host localhost.
            if host == "localhost" { return nil }
        } else {
            return nil
        }

        let path = normalizedPath(scheme: scheme, host: host, url: url)
        let query = queryItems(url)
        let components = path.split(separator: "/").map(String.init)
        var trekId = firstQuery(query, keys: ["trek", "trekId"])
        var questId = firstQuery(query, keys: ["quest", "questId"])
        if trekId == nil, components.count >= 2, components[0] == "t" {
            trekId = components[1]
        }
        if questId == nil, components.count >= 2, components[0] == "q" {
            questId = components[1]
        }
        if trekId == nil, components.count >= 3, components[0] == "play", components[1] == "t" {
            trekId = components[2]
        }
        if questId == nil, components.count >= 3, components[0] == "play", components[1] == "q" {
            questId = components[2]
        }
        return Parts(path: path, query: query, trekId: trekId, questId: questId)
    }

    private static func normalizedPath(scheme: String, host: String, url: URL) -> String {
        let rawPath = url.path
        if scheme == "tr3k" {
            if host.isEmpty || host == "localhost" {
                return rawPath.isEmpty ? "/" : rawPath
            }
            if rawPath.isEmpty || rawPath == "/" {
                return "/\(host)"
            }
            let suffix = rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
            return "/\(host)\(suffix)"
        }
        if rawPath.isEmpty { return "/" }
        return rawPath.hasSuffix("/") || rawPath == "/" ? rawPath : rawPath
    }

    private static func queryItems(_ url: URL) -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return [:]
        }
        var query: [String: String] = [:]
        for item in items {
            guard let value = item.value else { continue }
            query[item.name] = value
        }
        return query
    }

    private static func firstQuery(_ query: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = query[key], !value.isEmpty { return value }
        }
        return nil
    }

    private static func url(from value: Any?) -> URL? {
        switch value {
        case let url as URL:
            return url
        case let url as NSURL:
            return url as URL
        case let text as String:
            return URL(string: text)
        default:
            return nil
        }
    }
}
