import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let session: Int
    let week: Int
    let updatedAt: Date?
    let hasError: Bool
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), session: 42, week: 58, updatedAt: Date(), hasError: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = currentEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func currentEntry() -> UsageEntry {
        let snapshot = UsageStore.load()
        return UsageEntry(date: Date(), session: snapshot.session, week: snapshot.week, updatedAt: snapshot.updatedAt, hasError: snapshot.hasError)
    }
}

struct ClaudeUsageBarWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: UsageEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 14) {
            usageBar(label: "Session", value: entry.session)
            usageBar(label: "Woche", value: entry.week)
            Spacer(minLength: 0)
            footer
        }
        .padding()
    }

    private var mediumView: some View {
        HStack(spacing: 28) {
            usageGauge(label: "Session", value: entry.session)
            usageGauge(label: "Woche", value: entry.week)
            Spacer(minLength: 0)
            VStack(alignment: .trailing) {
                Spacer()
                footer
            }
        }
        .padding()
    }

    private var footer: some View {
        Group {
            if entry.hasError {
                Text("Fehler beim Abruf")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
            } else if let updatedAt = entry.updatedAt {
                Text(updatedAt, style: .relative)
                    .font(.system(size: 9))
                    .foregroundStyle(.black)
            } else {
                Text("Keine Daten")
                    .font(.system(size: 9))
                    .foregroundStyle(.black)
            }
        }
    }

    private func usageBar(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black)
            GeometryReader { geo in
                let fraction = CGFloat(min(max(value, 0), 100)) / 100
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(color(for: value))
                        .frame(width: geo.size.width * fraction)
                    Text("\(value)%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: geo.size.width, alignment: .center)
                }
            }
            .frame(height: 20)
        }
    }

    private func usageGauge(label: String, value: Int) -> some View {
        VStack(spacing: 6) {
            Gauge(value: Double(value), in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                Text("\(value)%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(color(for: value))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func color(for value: Int) -> Color {
        switch value {
        case ..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }
}

struct ClaudeUsageBarWidget: Widget {
    let kind: String = "ClaudeUsageBarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            ClaudeUsageBarWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Usage")
        .description("Zeigt deine aktuelle Claude-Nutzung (Session & Woche).")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ClaudeUsageBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeUsageBarWidget()
    }
}
