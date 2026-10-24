import ActivityKit
import SwiftUI
import Tr3kActivityKit
import WidgetKit

/// Lock Screen and Dynamic Island UI for an active Tr3k.
/// `Tr3kNavigationAttributes` comes from the Tr3kActivityKit module, the same
/// module the shell uses to start the activity.
struct Tr3kNavigationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: Tr3kNavigationAttributes.self) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.trekName.isEmpty ? "Tr3k" : context.attributes.trekName)
                    .font(.headline)
                Text(context.state.instruction)
                    .font(.subheadline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if !context.state.distanceText.isEmpty {
                        Text(context.state.distanceText)
                    }
                    if !context.state.distanceText.isEmpty && !context.state.etaText.isEmpty {
                        Text("·")
                    }
                    if !context.state.etaText.isEmpty {
                        Text(context.state.etaText)
                    }
                }
                .font(.caption)
                if !context.state.stopName.isEmpty {
                    Text(context.state.stopName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(Color(red: 0.078, green: 0.067, blue: 0.055))
            .activitySystemActionForegroundColor(Color(red: 0.96, green: 0.55, blue: 0.22))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.distanceText.isEmpty ? "Tr3k" : context.state.distanceText)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.etaText)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.instruction)
                        .font(.subheadline)
                        .lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: "location.fill")
            } compactTrailing: {
                Text(context.state.distanceText.isEmpty ? "Tr3k" : context.state.distanceText)
                    .font(.caption2)
            } minimal: {
                Image(systemName: "location.fill")
            }
            .keylineTint(Color(red: 0.96, green: 0.55, blue: 0.22))
        }
    }
}

@main
struct Tr3kLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        Tr3kNavigationLiveActivity()
    }
}
