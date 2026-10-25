import ActivityKit
import SwiftUI
import Tr3kActivityKit
import WidgetKit

/// Lock Screen and Dynamic Island for an active Tr3k.
/// Black field, white type, gold only while a live drop or a rare hunt is up.
/// `Tr3kNavigationAttributes` is the same module the shell uses to start the activity.
struct Tr3kNavigationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: Tr3kNavigationAttributes.self) { context in
            Tr3kLockScreen(face: Tr3kLiveFace(attributes: context.attributes, state: context.state))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Tr3kIslandStat(
                        text: Tr3kLiveFace(attributes: context.attributes, state: context.state).leading,
                        prominent: true
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Tr3kIslandStat(
                        text: Tr3kLiveFace(attributes: context.attributes, state: context.state).trailing,
                        prominent: false
                    )
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Tr3kIslandBottom(face: Tr3kLiveFace(attributes: context.attributes, state: context.state))
                }
            } compactLeading: {
                Text(Tr3kLiveFace(attributes: context.attributes, state: context.state).compactLeading)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
            } compactTrailing: {
                Text(Tr3kLiveFace(attributes: context.attributes, state: context.state).compactTrailing)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Tr3kLiveFace(attributes: context.attributes, state: context.state).accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } minimal: {
                Text(Tr3kLiveFace(attributes: context.attributes, state: context.state).minimal)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Tr3kLiveFace(attributes: context.attributes, state: context.state).accent)
            }
            .widgetURL(Tr3kLiveFace(attributes: context.attributes, state: context.state).url)
            .keylineTint(Tr3kLiveFace(attributes: context.attributes, state: context.state).accent)
        }
    }
}

private struct Tr3kLiveFace {
    var kicker: String
    var title: String
    var metrics: String
    var action: String
    var progress: String
    var leading: String
    var trailing: String
    var compactLeading: String
    var compactTrailing: String
    var minimal: String
    var gold: Bool
    var accent: Color
    var url: URL
    var accessibilityText: String

    init(attributes: Tr3kNavigationAttributes, state: Tr3kNavigationAttributes.ContentState) {
        let trek = attributes.trekName.trimmingCharacters(in: .whitespacesAndNewlines)
        let stop = state.stopName.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = stop.isEmpty ? (trek.isEmpty ? "Tr3k" : trek) : stop
        title = place
        if !stop.isEmpty, !trek.isEmpty, trek.caseInsensitiveCompare(stop) != .orderedSame {
            kicker = "TR3K  ·  \(trek)"
        } else {
            kicker = "TR3K"
        }
        progress = state.progressText.trimmingCharacters(in: .whitespacesAndNewlines)
        let distance = state.distanceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let eta = state.etaText.trimmingCharacters(in: .whitespacesAndNewlines)
        var metricParts: [String] = []
        if !distance.isEmpty { metricParts.append(distance) }
        if !eta.isEmpty, eta != distance { metricParts.append(eta) }
        metrics = metricParts.joined(separator: "  ·  ")
        let rawAction = state.action.trimmingCharacters(in: .whitespacesAndNewlines)
        action = rawAction.isEmpty ? Tr3kLiveActivityCopy.drive : rawAction
        leading = progress.isEmpty ? "Tr3k" : progress
        if !distance.isEmpty, distance != "Here" {
            trailing = distance
        } else if !eta.isEmpty {
            trailing = eta
        } else {
            trailing = Tr3kLiveActivityCopy.compactTrailing(action: action, distanceText: distance)
        }
        compactLeading = progress.isEmpty ? "Tr3k" : progress
        compactTrailing = Tr3kLiveActivityCopy.compactTrailing(action: action, distanceText: distance)
        if state.tone == "drop" {
            minimal = "●"
        } else if let first = progress.split(separator: "/").first, !first.isEmpty {
            minimal = String(first)
        } else {
            minimal = "T"
        }
        gold = state.tone == "drop" || state.tone == "rare"
        accent = gold ? Tr3kChrome.gold : Color.white
        url = Tr3kLiveActivityCopy.playURL(id: attributes.trekId, kind: attributes.kind)
        var spoken = ["Tr3k", place, action]
        if !progress.isEmpty { spoken.append(progress) }
        if !metrics.isEmpty { spoken.append(metrics) }
        accessibilityText = spoken.joined(separator: ", ")
    }
}

private enum Tr3kChrome {
    static let black = Color.black
    static let silver = Color.white.opacity(0.62)
    static let gold = Color(red: 0.855, green: 0.722, blue: 0.455)
}

private struct Tr3kLockScreen: View {
    let face: Tr3kLiveFace

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(face.kicker)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(face.gold ? Tr3kChrome.gold : Tr3kChrome.silver)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !face.progress.isEmpty {
                    Text(face.progress)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.78))
                }
            }
            Text(face.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !face.metrics.isEmpty {
                Text(face.metrics)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Tr3kChrome.silver)
                    .lineLimit(1)
            }
            Text(face.action)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(face.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .tr3kLiveChrome(accent: face.accent)
        .widgetURL(face.url)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(face.accessibilityText)
    }
}

private struct Tr3kIslandStat: View {
    let text: String
    let prominent: Bool

    var body: some View {
        Text(text)
            .font(prominent ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(prominent ? Color.white : Tr3kChrome.silver)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

private struct Tr3kIslandBottom: View {
    let face: Tr3kLiveFace

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(face.action)
                .font(.headline.weight(.bold))
                .foregroundStyle(face.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(face.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Tr3kChrome.silver)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    @ViewBuilder
    func tr3kLiveChrome(accent: Color) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(Tr3kChrome.black, for: .widget)
                .activityBackgroundTint(Tr3kChrome.black)
                .activitySystemActionForegroundColor(accent)
        } else {
            self.activityBackgroundTint(Tr3kChrome.black)
                .activitySystemActionForegroundColor(accent)
        }
    }
}

@main
struct Tr3kLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        Tr3kNavigationLiveActivity()
    }
}
