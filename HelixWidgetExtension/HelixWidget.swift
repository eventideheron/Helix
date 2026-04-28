// Widgets/HelixWidget.swift
// Lock screen + home screen widget. Reads from shared SwiftData store.
// Never calls HealthKit directly — data flows from main app only.

import WidgetKit
import SwiftUI
import SwiftData

// MARK: — Timeline entry

struct HelixWidgetEntry: TimelineEntry {
    let date:    Date
    let display: HelixWidgetDisplayRecord?
}

// MARK: — Provider

struct HelixWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> HelixWidgetEntry {
        HelixWidgetEntry(date: Date(), display: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (HelixWidgetEntry) -> Void) {
        completion(HelixWidgetEntry(date: Date(), display: loadLatestDisplay()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HelixWidgetEntry>) -> Void) {
        let display = loadLatestDisplay()
        let entry   = HelixWidgetEntry(date: Date(), display: display)
        let refresh = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 6, minute: 0),
            matchingPolicy: .nextTime
        )!
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func loadLatestDisplay() -> HelixWidgetDisplayRecord? {
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: helixAppGroupID)?
            .appendingPathComponent("helix.store")
        else { return nil }

        let schema = Schema(versionedSchema: HelixSchemaV2.self)
        let config = ModelConfiguration(url: groupURL)
        guard let container = try? ModelContainer(
            for: schema,
            migrationPlan: HelixMigrationPlan.self,
            configurations: config
        ) else { return nil }

        let context    = ModelContext(container)
        let descriptor = FetchDescriptor<HelixDailyRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let canonical = try? context.fetch(descriptor).first else { return nil }
        return HelixWidgetDisplayRecord(from: canonical)
    }
}

// MARK: — Widget bundle

@main
struct HelixWidgetBundle: WidgetBundle {
    var body: some Widget { HelixWidget() }
}

struct HelixWidget: Widget {
    let kind = "HelixWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HelixWidgetProvider()) { entry in
            HelixWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Helix")
        .description("Your daily Helix Index.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}
