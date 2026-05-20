// HelixWidget/HelixWidgetProvider.swift
// Reads the latest scores from shared App Group UserDefaults.
// Primary refresh is triggered by WidgetCenter.shared.reloadAllTimelines() in the main app.
// Background fallback: 30-minute policy reload keeps the widget alive without user interaction.

import WidgetKit
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
        completion(HelixWidgetEntry(date: Date(), display: HelixWidgetDataStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HelixWidgetEntry>) -> Void) {
        let record  = HelixWidgetDataStore.load()
        let entry   = HelixWidgetEntry(date: Date(), display: record)
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}
