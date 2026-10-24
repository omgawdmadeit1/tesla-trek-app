import ActivityKit
import Foundation

@available(iOS 16.2, *)
public enum Tr3kLiveActivityController {
    private static var lastState = Tr3kNavigationAttributes.ContentState(
        instruction: "Tr3k navigation",
        distanceText: "",
        etaText: "",
        stopName: ""
    )

    @MainActor
    public static func activitiesEnabled() -> Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    @MainActor
    public static func start(trekId: String, trekName: String, fields: [String: Any]) async throws -> String {
        let state = merged(fields)
        if let existing = Activity<Tr3kNavigationAttributes>.activities.first(where: { $0.attributes.trekId == trekId && !trekId.isEmpty }) {
            await existing.update(ActivityContent(state: state, staleDate: nil))
            return existing.id
        }
        for activity in Activity<Tr3kNavigationAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let name = trekName.isEmpty ? "Tr3k" : trekName
        let attributes = Tr3kNavigationAttributes(trekName: name, trekId: trekId)
        let activity = try Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        return activity.id
    }

    @MainActor
    public static func update(fields: [String: Any]) async -> Bool {
        let activities = Activity<Tr3kNavigationAttributes>.activities
        guard !activities.isEmpty else { return false }
        let state = merged(fields)
        for activity in activities {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        return true
    }

    @MainActor
    public static func end(immediate: Bool) async {
        let policy: ActivityUIDismissalPolicy = immediate ? .immediate : .default
        let state = lastState
        for activity in Activity<Tr3kNavigationAttributes>.activities {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: policy)
        }
    }

    public static func text(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func merged(_ fields: [String: Any]) -> Tr3kNavigationAttributes.ContentState {
        let next = Tr3kNavigationAttributes.ContentState(
            instruction: text(fields["instruction"]) ?? lastState.instruction,
            distanceText: text(fields["distanceText"]) ?? text(fields["distance"]) ?? lastState.distanceText,
            etaText: text(fields["etaText"]) ?? text(fields["eta"]) ?? lastState.etaText,
            stopName: text(fields["stopName"]) ?? lastState.stopName
        )
        lastState = next
        return next
    }
}
