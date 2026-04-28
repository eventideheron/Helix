// HelixWidgetExtension/HelixWidgetProvider.swift
// Reads the latest HelixDailyRecord from shared SwiftData storage.
// Never calls HealthKit. Never imports engine or domain layers.
// Widget refreshes at 6:00 AM daily — aligned with post-sleep score calculation.

import WidgetKit
import SwiftData
import Foundation

struct HelixWidgetEntry: TimelineEntry {
    let date:    Date
    let display: HelixWidgetDisplayRecord?
}

struct HelixWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> HelixWidgetEntry {
        HelixWidgetEntry(date: Date(), display: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (HelixWidgetEntry) -> Void) {
        completion(HelixWidgetEntry(date: Date(), display: loadLatestDisplay()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HelixWidgetEntry>) -> Void) {
        let entry   = HelixWidgetEntry(date: Date(), display: loadLatestDisplay())
        let refresh = nextMorningAt6()
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    // MARK: — Private

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

    private func nextMorningAt6() -> Date {
        Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 6, minute: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600 * 8)
    }
}
