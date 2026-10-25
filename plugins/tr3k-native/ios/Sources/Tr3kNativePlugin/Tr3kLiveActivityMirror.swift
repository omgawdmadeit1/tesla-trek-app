import Foundation
import Tr3kActivityKit

/// Keeps the existing Live Activity on the same bridge the page already calls.
///
/// `startLiveActivity` / `updateLiveActivity` / `endLiveActivity` stay the
/// explicit channel. Map, route, stops, spoken directions, arrival, and a
/// live drop write the same content state, so the lock screen moves when the
/// page only drives navigation.
@available(iOS 16.2, *)
@MainActor
final class Tr3kLiveActivityMirror {
    static let shared = Tr3kLiveActivityMirror()

    private struct Stop {
        var id: String
        var name: String
        var lat: Double
        var lng: Double
    }

    private enum Job {
        case sync(create: Bool, fields: [String: Any])
        case end(immediate: Bool, markComplete: Bool)
    }

    private struct Outcome {
        var id: String?
        var reason: String?
        var ended = false
    }

    private var stops: [Stop] = []
    private var arrived = Set<String>()
    private var target = 0
    private var holdingArrival = false
    private var trekId = ""
    private var trekName = "Tr3k"
    private var kind = "trek"
    private var action = Tr3kLiveActivityCopy.drive
    private var tone = "nav"
    private var wantsActivity = false
    private var mapVisible = false
    private var closing = false
    private var webOwnsProgress = false
    private var explicitComplete = false
    private var distanceFreshUntil = Date.distantPast
    private var lastLocationPush = Date.distantPast
    private var lastDistance = ""
    private var lastETA = ""
    private var hideWork: DispatchWorkItem?
    private var chain: Task<Void, Never> = Task {}

    private init() {}

    func start(_ fields: [String: Any]) async -> [String: Any] {
        guard Tr3kLiveActivityController.activitiesEnabled() else {
            return ["started": false, "reason": "disabled"]
        }
        hideWork?.cancel()
        closing = false
        wantsActivity = true
        absorb(fields)
        let outcome = await enqueue(.sync(create: true, fields: fields))
        if let id = outcome.id {
            return ["started": true, "id": id]
        }
        return ["started": false, "reason": outcome.reason ?? "unavailable"]
    }

    func update(_ fields: [String: Any]) async -> [String: Any] {
        absorb(fields)
        switch Tr3kLiveActivityCopy.ending(in: fields) {
        case .complete:
            explicitComplete = true
            let outcome = await enqueue(endJob())
            return ["updated": false, "ended": outcome.ended]
        case .cancel:
            wantsActivity = false
            let outcome = await enqueue(.end(immediate: true, markComplete: false))
            return ["updated": false, "ended": outcome.ended]
        case .none:
            let outcome = await enqueue(.sync(create: wantsActivity, fields: fields))
            return ["updated": outcome.id != nil]
        }
    }

    func end(dismissal: String?) async -> [String: Any] {
        hideWork?.cancel()
        wantsActivity = false
        closing = true
        _ = await enqueue(endJob(dismissal: dismissal))
        return ["ended": true]
    }

    func noteOffline(_ raw: [String: Any]) {
        guard let active = Self.dictionary(raw["active"]) else { return }
        let previousId = trekId
        let previousName = trekName
        if let id = Tr3kLiveActivityCopy.text(active["id"])
            ?? Tr3kLiveActivityCopy.text(active["trekId"])
            ?? Tr3kLiveActivityCopy.text(active["questId"]) {
            trekId = Tr3kLiveActivityCopy.clip(id, 128)
        }
        if let name = Tr3kLiveActivityCopy.text(active["name"])
            ?? Tr3kLiveActivityCopy.text(active["placeName"])
            ?? Tr3kLiveActivityCopy.text(active["title"]) {
            trekName = Tr3kLiveActivityCopy.clip(name, 80)
        }
        let activeKind = Tr3kLiveActivityCopy.text(active["kind"])?.lowercased()
        if activeKind == "quest" || Tr3kLiveActivityCopy.text(active["questId"]) != nil {
            kind = "quest"
        } else if activeKind == "trek" {
            kind = "trek"
        }
        let learned = trekId != previousId || trekName != previousName
        guard wantsActivity, learned else { return }
        poke(.sync(create: true, fields: [:]))
    }

    func noteMap(visible: Bool, fields: [String: Any]) {
        mapVisible = visible
        if visible {
            hideWork?.cancel()
            closing = false
            let resolved = Tr3kLiveActivityCopy.identity(
                fields: fields,
                fallback: Tr3kLiveActivityCopy.Identity(id: trekId, name: trekName, kind: kind)
            )
            trekId = resolved.id
            if !resolved.name.isEmpty { trekName = resolved.name }
            kind = resolved.kind
            guard !stops.isEmpty || wantsActivity else { return }
            if !stops.isEmpty { wantsActivity = true }
            poke(.sync(create: wantsActivity, fields: navigationFields(includeAction: !holdingArrival)))
            return
        }
        guard wantsActivity else { return }
        closing = true
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.closing else { return }
                self.wantsActivity = false
                _ = await self.enqueue(self.endJob())
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    func noteStops(_ rawStops: [Any]) {
        replaceStops(rawStops)
        guard mapVisible || wantsActivity else { return }
        if mapVisible, !stops.isEmpty { wantsActivity = true }
        guard wantsActivity else { return }
        poke(.sync(create: true, fields: navigationFields(includeAction: !holdingArrival)))
    }

    func noteRoute(_ fields: [String: Any]) {
        absorb(fields)
        if let raw = fields["stops"] {
            let rows = Self.rows(raw)
            if !rows.isEmpty {
                replaceStops(rows)
            }
        }
        guard mapVisible || wantsActivity else { return }
        if mapVisible, !stops.isEmpty { wantsActivity = true }
        guard wantsActivity else { return }
        poke(.sync(create: true, fields: navigationFields(includeAction: !holdingArrival)))
    }

    func noteArrival(_ stopId: String) {
        arrived.insert(stopId)
        if let index = stops.firstIndex(where: { $0.id == stopId }) {
            target = index
        }
        holdingArrival = true
        let drop = Tr3kLiveDropStore.shared.drop(for: stopId) != nil
        action = drop ? Tr3kLiveActivityCopy.join : Tr3kLiveActivityCopy.park
        tone = drop ? "drop" : "arrive"
        var fields: [String: Any] = [
            "action": action,
            "tone": tone,
            "instruction": drop ? "Only people at this stop." : "You've arrived",
            "distanceText": "Here",
            "etaText": ""
        ]
        if let index = stops.firstIndex(where: { $0.id == stopId }), !stops[index].name.isEmpty {
            fields["stopName"] = stops[index].name
        }
        if let progress = nativeProgress() {
            fields["progressText"] = progress
        }
        poke(.sync(create: false, fields: fields))
    }

    func noteSpeech(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, wantsActivity, !closing else { return }
        if tone == "drop" {
            let inferred = Tr3kLiveActivityCopy.inferredAction(in: trimmed)
            guard inferred == Tr3kLiveActivityCopy.drive || inferred == Tr3kLiveActivityCopy.complete else { return }
        }
        if Tr3kLiveActivityCopy.inferredAction(in: trimmed) == Tr3kLiveActivityCopy.complete {
            explicitComplete = true
        }
        var fields: [String: Any] = ["instruction": Tr3kLiveActivityCopy.clip(trimmed, 140)]
        if let inferred = Tr3kLiveActivityCopy.inferredAction(in: trimmed) {
            action = inferred
            if inferred == Tr3kLiveActivityCopy.join {
                tone = "drop"
            } else if inferred == Tr3kLiveActivityCopy.drive || inferred == Tr3kLiveActivityCopy.complete {
                tone = "nav"
            }
            if inferred == Tr3kLiveActivityCopy.park || inferred == Tr3kLiveActivityCopy.hunt {
                if tone != "rare" { tone = "arrive" }
                holdingArrival = true
            }
            if inferred == Tr3kLiveActivityCopy.drive, holdingArrival {
                holdingArrival = false
                advanceTarget()
                tone = "nav"
            }
            fields["action"] = action
            fields["tone"] = tone
        }
        if action == Tr3kLiveActivityCopy.drive, Date() > distanceFreshUntil {
            if let distance = Tr3kLiveActivityCopy.spokenDistance(trimmed) {
                fields["distanceText"] = distance
                lastDistance = distance
            }
            if let eta = Tr3kLiveActivityCopy.spokenETA(trimmed) {
                fields["etaText"] = eta
                lastETA = eta
            }
        }
        if let progress = nativeProgress() {
            fields["progressText"] = progress
        }
        if stops.indices.contains(target), !stops[target].name.isEmpty, !holdingArrival {
            fields["stopName"] = stops[target].name
        }
        poke(.sync(create: false, fields: fields))
    }

    func noteLiveDrop(stopId: String) {
        guard wantsActivity || holdingArrival else { return }
        action = Tr3kLiveActivityCopy.join
        tone = "drop"
        holdingArrival = true
        var fields: [String: Any] = [
            "action": action,
            "tone": tone,
            "instruction": "Only people at this stop.",
            "liveDrop": true
        ]
        if let index = stops.firstIndex(where: { $0.id == stopId }) {
            target = index
            if !stops[index].name.isEmpty {
                fields["stopName"] = stops[index].name
            }
        }
        if let progress = nativeProgress() {
            fields["progressText"] = progress
        }
        poke(.sync(create: false, fields: fields))
    }

    func noteHunt(rare: Bool = false) {
        guard wantsActivity, tone != "drop" else { return }
        action = Tr3kLiveActivityCopy.hunt
        tone = rare ? "rare" : "arrive"
        holdingArrival = true
        var fields: [String: Any] = [
            "action": action,
            "tone": tone
        ]
        if rare { fields["rare"] = true }
        poke(.sync(create: false, fields: fields))
    }

    func noteLocation(lat: Double, lng: Double, speed: Double) {
        guard wantsActivity, !closing else { return }
        guard action == Tr3kLiveActivityCopy.drive, tone != "drop", !holdingArrival else { return }
        guard Date() > distanceFreshUntil else { return }
        guard Date().timeIntervalSince(lastLocationPush) >= 10 else { return }
        guard stops.indices.contains(target) else { return }
        let stop = stops[target]
        guard stop.lat != 0 || stop.lng != 0 else { return }
        let meters = Self.meters(fromLat: lat, fromLng: lng, toLat: stop.lat, toLng: stop.lng)
        let distance = Tr3kLiveActivityCopy.formatMeters(meters)
        let eta = Tr3kLiveActivityCopy.formatETA(meters: meters, speedMps: speed > 0 ? speed : nil)
        guard distance != lastDistance || eta != lastETA else { return }
        lastDistance = distance
        lastETA = eta
        lastLocationPush = Date()
        var fields: [String: Any] = [
            "distanceText": distance,
            "etaText": eta
        ]
        if let progress = nativeProgress() {
            fields["progressText"] = progress
        }
        poke(.sync(create: false, fields: fields))
    }

    // MARK: - Session

    private func absorb(_ fields: [String: Any]) {
        let resolved = Tr3kLiveActivityCopy.identity(
            fields: fields,
            fallback: Tr3kLiveActivityCopy.Identity(id: trekId, name: trekName, kind: kind)
        )
        trekId = resolved.id
        if !resolved.name.isEmpty {
            trekName = resolved.name
        }
        kind = resolved.kind
        if Tr3kLiveActivityCopy.progress(from: fields) != nil {
            webOwnsProgress = true
        }
        let distance = Self.lookup(fields, ["distanceText", "distance"])
        let eta = Self.lookup(fields, ["etaText", "eta"])
        if (distance.found && !distance.value.isEmpty) || (eta.found && !eta.value.isEmpty) {
            distanceFreshUntil = Date().addingTimeInterval(12)
            if distance.found { lastDistance = distance.value }
            if eta.found { lastETA = eta.value }
        }
        let preview = Tr3kLiveActivityCopy.next(
            from: Tr3kNavigationAttributes.ContentState(
                instruction: "",
                distanceText: "",
                etaText: "",
                stopName: "",
                progressText: "",
                action: action,
                tone: tone
            ),
            fields: fields
        )
        let specifiesAction = Self.lookup(fields, ["action", "nextAction", "next", "phase", "status", "instruction", "step", "liveDrop", "live", "rare", "rarity"]).found
        if specifiesAction {
            action = preview.action
            tone = preview.tone
        }
        if Tr3kLiveActivityCopy.ending(in: fields) == .complete {
            explicitComplete = true
        }
    }

    private func replaceStops(_ rawStops: [Any]) {
        var parsed: [Stop] = []
        for (index, row) in rawStops.prefix(20).enumerated() {
            guard let object = Self.dictionary(row) else { continue }
            guard let lat = Self.coordinate(object, keys: ["lat", "latitude"], range: -90...90),
                  let lng = Self.coordinate(object, keys: ["lng", "lon", "longitude"], range: -180...180) else { continue }
            let id = Tr3kLiveActivityCopy.text(object["id"]) ?? String(index)
            let name = Tr3kLiveActivityCopy.text(object["name"]) ?? ""
            parsed.append(Stop(id: id, name: name, lat: lat, lng: lng))
        }
        guard !parsed.isEmpty else { return }
        let same = parsed.map(\.id) == stops.map(\.id)
        stops = parsed
        arrived = arrived.filter { id in parsed.contains { $0.id == id } }
        if !same, !holdingArrival {
            target = parsed.indices.first { !arrived.contains(parsed[$0].id) } ?? 0
        } else {
            target = min(target, parsed.count - 1)
        }
    }

    private func advanceTarget() {
        guard !stops.isEmpty else { return }
        target = stops.indices.first { !arrived.contains(stops[$0].id) } ?? (stops.count - 1)
    }

    private func nativeProgress() -> String? {
        guard !webOwnsProgress, !stops.isEmpty else { return nil }
        let index = min(max(target, 0), stops.count - 1)
        return Tr3kLiveActivityCopy.progress(index: index + 1, count: stops.count)
    }

    private func navigationFields(includeAction: Bool) -> [String: Any] {
        var fields: [String: Any] = [:]
        if includeAction {
            fields["action"] = action
            fields["tone"] = tone
        }
        if let progress = nativeProgress() {
            fields["progressText"] = progress
        }
        if stops.indices.contains(target), !stops[target].name.isEmpty {
            fields["stopName"] = stops[target].name
        }
        return fields
    }

    private var allArrived: Bool {
        !stops.isEmpty && stops.allSatisfy { arrived.contains($0.id) }
    }

    private func endJob(dismissal: String? = nil) -> Job {
        if dismissal == "immediate" {
            return .end(immediate: true, markComplete: false)
        }
        let finished = explicitComplete || allArrived
        if dismissal == "default" {
            return .end(immediate: false, markComplete: finished)
        }
        if finished {
            return .end(immediate: false, markComplete: true)
        }
        return .end(immediate: true, markComplete: false)
    }

    private func resetSession() {
        stops = []
        arrived = []
        target = 0
        holdingArrival = false
        wantsActivity = false
        mapVisible = false
        closing = false
        webOwnsProgress = false
        explicitComplete = false
        action = Tr3kLiveActivityCopy.drive
        tone = "nav"
        distanceFreshUntil = .distantPast
        lastDistance = ""
        lastETA = ""
        trekId = ""
        trekName = "Tr3k"
        kind = "trek"
    }

    // MARK: - Queue

    @discardableResult
    private func enqueue(_ job: Job) async -> Outcome {
        let previous = chain
        let next = Task { @MainActor () -> Outcome in
            await previous.value
            return await self.run(job)
        }
        chain = Task { _ = await next.value }
        return await next.value
    }

    private func poke(_ job: Job) {
        Task { _ = await self.enqueue(job) }
    }

    private func run(_ job: Job) async -> Outcome {
        switch job {
        case let .sync(create, fields):
            guard Tr3kLiveActivityController.activitiesEnabled() else {
                return Outcome(id: nil, reason: "disabled")
            }
            let result = await Tr3kLiveActivityController.sync(
                trekId: trekId,
                trekName: trekName,
                kind: kind,
                fields: fields,
                create: create || wantsActivity
            )
            return Outcome(id: result.id, reason: result.reason)
        case let .end(immediate, markComplete):
            await Tr3kLiveActivityController.end(immediate: immediate, markComplete: markComplete)
            resetSession()
            return Outcome(id: nil, reason: nil, ended: true)
        }
    }

    // MARK: - JS values

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        if value is NSNull { return nil }
        if let dict = value as? [String: Any] { return dict }
        if let dict = value as? NSDictionary {
            var object: [String: Any] = [:]
            for (key, raw) in dict {
                guard let key = key as? String else { continue }
                object[key] = raw
            }
            return object
        }
        return nil
    }

    private static func rows(_ value: Any?) -> [Any] {
        if let list = value as? [Any] { return list }
        if let list = value as? NSArray { return list.map { $0 } }
        return []
    }

    private static func coordinate(_ object: [String: Any], keys: [String], range: ClosedRange<Double>) -> Double? {
        for key in keys {
            guard let number = object[key] else { continue }
            let value: Double?
            if let double = number as? Double {
                value = double
            } else if let number = number as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                value = number.doubleValue
            } else if let text = number as? String {
                value = Double(text)
            } else {
                value = nil
            }
            if let value, value.isFinite, range.contains(value) { return value }
        }
        return nil
    }

    private static func lookup(_ fields: [String: Any], _ keys: [String]) -> (found: Bool, value: String) {
        for key in keys {
            guard let raw = fields[key] else { continue }
            return (true, Tr3kLiveActivityCopy.text(raw) ?? "")
        }
        return (false, "")
    }

    private static func meters(fromLat: Double, fromLng: Double, toLat: Double, toLng: Double) -> Double {
        let earth = 6_371_000.0
        let phi1 = fromLat * .pi / 180
        let phi2 = toLat * .pi / 180
        let dPhi = (toLat - fromLat) * .pi / 180
        let dLambda = (toLng - fromLng) * .pi / 180
        let h = sin(dPhi / 2) * sin(dPhi / 2)
            + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        return 2 * earth * asin(min(1, sqrt(h)))
    }
}
