import ActivityKit
import Foundation

/// Starts, updates, and ends the single in-progress Tr3k Live Activity.
/// Callers pass the same field bag `startLiveActivity` / `updateLiveActivity`
/// already use. Missing keys keep the content that is on screen.
@available(iOS 16.2, *)
public enum Tr3kLiveActivityController {
    private static var lastState = Tr3kNavigationAttributes.ContentState.empty

    public struct SyncResult {
        public var id: String?
        public var reason: String?
    }

    @MainActor
    public static func activitiesEnabled() -> Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Merge `fields` onto the live activity. Creates one when `create` is true
    /// and nothing is on screen. A different trek id replaces the previous activity
    /// so two hunts are never on the lock screen together.
    @MainActor
    public static func sync(
        trekId: String,
        trekName: String,
        kind: String,
        fields: [String: Any],
        create: Bool
    ) async -> SyncResult {
        let activities = Activity<Tr3kNavigationAttributes>.activities.filter(Self.isLive)
        let current = activities.first
        let incomingId = trekId.trimmingCharacters(in: .whitespacesAndNewlines)
        let incomingName = trekName.trimmingCharacters(in: .whitespacesAndNewlines)
        let incomingKind = kind == "quest" ? "quest" : "trek"
        let currentId = current?.attributes.trekId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let newTrek = !incomingId.isEmpty && !currentId.isEmpty && incomingId != currentId
        let base = newTrek ? Tr3kNavigationAttributes.ContentState.empty : (current?.content.state ?? lastState)
        let state = Tr3kLiveActivityCopy.next(from: base, fields: fields)
        lastState = state

        let resolvedName = {
            if !incomingName.isEmpty { return incomingName }
            if let existing = current?.attributes.trekName, !existing.isEmpty, !newTrek { return existing }
            return "Tr3k"
        }()
        let resolvedId = {
            if !incomingId.isEmpty { return incomingId }
            if !newTrek { return currentId }
            return ""
        }()
        let resolvedKind = {
            if incomingKind == "quest" || kind == "quest" { return "quest" }
            if !newTrek, current?.attributes.kind == "quest", incomingId.isEmpty { return "quest" }
            return "trek"
        }()

        if current == nil {
            guard create else { return SyncResult(id: nil, reason: nil) }
            do {
                let id = try await request(
                    trekId: resolvedId,
                    trekName: resolvedName,
                    kind: resolvedKind,
                    state: state
                )
                return SyncResult(id: id, reason: nil)
            } catch {
                return SyncResult(id: nil, reason: error.localizedDescription)
            }
        }

        let restart = shouldRestart(
            existingId: currentId,
            existingName: current?.attributes.trekName ?? "",
            existingKind: current?.attributes.kind ?? "trek",
            incomingId: resolvedId,
            incomingName: resolvedName,
            incomingKind: resolvedKind
        )
        if restart {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            do {
                let id = try await request(
                    trekId: resolvedId,
                    trekName: resolvedName,
                    kind: resolvedKind,
                    state: state
                )
                return SyncResult(id: id, reason: nil)
            } catch {
                return SyncResult(id: nil, reason: error.localizedDescription)
            }
        }

        let primary = activities[0]
        if activities.count > 1 {
            for activity in activities.dropFirst() {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        await primary.update(ActivityContent(state: state, staleDate: nil))
        return SyncResult(id: primary.id, reason: nil)
    }

    @MainActor
    public static func end(immediate: Bool, markComplete: Bool) async {
        let finishing = Activity<Tr3kNavigationAttributes>.activities.filter(Self.isLive)
        var state = finishing.first?.content.state ?? lastState
        if markComplete {
            state = Tr3kLiveActivityCopy.next(from: state, fields: [
                "action": Tr3kLiveActivityCopy.complete,
                "tone": "nav",
                "instruction": "Tr3k complete",
                "distanceText": "",
                "etaText": ""
            ])
        }
        lastState = Tr3kNavigationAttributes.ContentState.empty
        let policy: ActivityUIDismissalPolicy = immediate
            ? .immediate
            : .after(Date().addingTimeInterval(Tr3kLiveActivityCopy.endedLinger))
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in finishing {
            await activity.end(content, dismissalPolicy: policy)
        }
    }

    private static func isLive(_ activity: Activity<Tr3kNavigationAttributes>) -> Bool {
        switch activity.activityState {
        case .active, .stale:
            return true
        case .ended, .dismissed:
            return false
        @unknown default:
            return true
        }
    }

    public static func text(_ value: Any?) -> String? {
        Tr3kLiveActivityCopy.text(value)
    }

    private static func shouldRestart(
        existingId: String,
        existingName: String,
        existingKind: String,
        incomingId: String,
        incomingName: String,
        incomingKind: String
    ) -> Bool {
        if !incomingId.isEmpty, existingId.isEmpty { return true }
        if !incomingId.isEmpty, !existingId.isEmpty, incomingId != existingId { return true }
        if incomingKind == "quest", existingKind != "quest", !incomingId.isEmpty { return true }
        let incomingGeneric = incomingName.isEmpty || incomingName == "Tr3k"
        let existingGeneric = existingName.isEmpty || existingName == "Tr3k"
        if !incomingGeneric, existingGeneric, incomingName != existingName { return true }
        return false
    }

    private static func request(
        trekId: String,
        trekName: String,
        kind: String,
        state: Tr3kNavigationAttributes.ContentState
    ) async throws -> String {
        let name = trekName.isEmpty ? "Tr3k" : trekName
        let attributes = Tr3kNavigationAttributes(trekName: name, trekId: trekId, kind: kind)
        let activity = try Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        return activity.id
    }
}
