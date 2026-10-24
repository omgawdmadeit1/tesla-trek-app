import SwiftUI
import Tr3kAppGroup
import WidgetKit

struct Tr3kWidgetEntry: TimelineEntry {
    let date: Date
    let model: Tr3kWidgetModel
}

struct Tr3kWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> Tr3kWidgetEntry {
        Tr3kWidgetEntry(date: Date(), model: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (Tr3kWidgetEntry) -> Void) {
        let model = context.isPreview ? Tr3kWidgetModel.placeholder : Tr3kOfflineCache.snapshot()
        completion(Tr3kWidgetEntry(date: Date(), model: model))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Tr3kWidgetEntry>) -> Void) {
        let entry = Tr3kWidgetEntry(date: Date(), model: Tr3kOfflineCache.snapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct Tr3kHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Tr3kOfflineCache.widgetKind, provider: Tr3kWidgetProvider()) { entry in
            Tr3kWidgetView(entry: entry)
        }
        .configurationDisplayName("Tr3k")
        .description("Tr3ks near you, and a shortcut back to the one you started.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Tr3kWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Tr3kWidgetEntry

    private var accent: Color { Color(red: 0.96, green: 0.55, blue: 0.22) }

    var body: some View {
        Group {
            if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .tr3kWidgetBackground()
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tr3k")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            Spacer(minLength: 0)
            Text(smallTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(smallSubtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)
        }
        .padding(12)
        .widgetURL(entry.model.primaryLink)
        .accessibilityElement(children: .combine)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            Link(destination: entry.model.primaryLink) {
                HStack {
                    Text("Tr3k")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                    Spacer(minLength: 8)
                    Text(headerAction)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                }
            }
            if let active = entry.model.active {
                Link(destination: active.link) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(active.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let detail = detail(active) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !entry.model.nearby.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if entry.model.active != nil {
                        Text("Tr3ks near you")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    ForEach(Array(entry.model.nearby.prefix(3))) { ref in
                        Link(destination: ref.link) {
                            Text(ref.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            if entry.model.isEmpty {
                Text("Open Tr3k to start")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var smallTitle: String {
        if let active = entry.model.active { return active.name }
        if !entry.model.nearby.isEmpty { return "Tr3ks near you" }
        return "Start Tr3k"
    }

    private var smallSubtitle: String {
        if let active = entry.model.active {
            return detail(active) ?? "Continue"
        }
        if entry.model.nearby.isEmpty { return "Open Tr3k" }
        if entry.model.nearby.count == 1, let only = entry.model.nearby.first {
            return only.name
        }
        if let first = entry.model.nearby.first {
            return "\(first.name) and \(entry.model.nearby.count - 1) more"
        }
        return "Open Tr3k"
    }

    private var headerAction: String {
        if entry.model.active != nil { return "Continue" }
        if entry.model.nearby.isEmpty { return "Start Tr3k" }
        return "Tr3ks near you"
    }

    private func detail(_ ref: Tr3kPlaceRef) -> String? {
        if let copy = ref.gameCopy, !copy.isEmpty { return copy }
        if let category = ref.category, !category.isEmpty { return category }
        return nil
    }
}

private extension View {
    @ViewBuilder
    func tr3kWidgetBackground() -> some View {
        let color = Color(red: 0.078, green: 0.067, blue: 0.055)
        if #available(iOS 17.0, *) {
            containerBackground(color, for: .widget)
        } else {
            background(color)
        }
    }
}

@main
struct Tr3kWidgetBundle: WidgetBundle {
    var body: some Widget {
        Tr3kHomeWidget()
    }
}
