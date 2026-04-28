// HelixWidgetExtension/HelixWidgetProvider.swift
// Reads the latest HelixDailyRecord from shared SwiftData storage.
// Never calls HealthKit. Never imports engine or domain layers.
// Widget refreshes at 6:00 AM daily — aligned with post-sleep score calculation.

import WidgetKit
import SwiftData
import Foundation

struct HelixWidgetEntry: TimelineEntry {
    let date:   Date
    let record: HelixDailyRecord?
}

struct HelixWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> HelixWidgetEntry {
        HelixWidgetEntry(date: Date(), record: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (HelixWidgetEntry) -> Void) {
        completion(HelixWidgetEntry(date: Date(), record: latestRecord()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HelixWidgetEntry>) -> Void) {
        let entry   = HelixWidgetEntry(date: Date(), record: latestRecord())
        let refresh = nextMorningAt6()
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    // MARK: — Private

    private func latestRecord() -> HelixDailyRecord? {
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: helixAppGroupID)?
            .appendingPathComponent("helix.store")
        else { return nil }

        let schema = Schema([
            HelixDailyRecord.self,
            HelixBaselineSnapshot.self,
            HelixTriggerRecord.self
        ])
        let config = ModelConfiguration(url: groupURL)
        guard let container = try? ModelContainer(for: schema, configurations: config) else { return nil }

        let context    = ModelContext(container)
        let descriptor = FetchDescriptor<HelixDailyRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try? context.fetch(descriptor).first
    }

    private func nextMorningAt6() -> Date {
        Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 6, minute: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600 * 8)
    }
}
