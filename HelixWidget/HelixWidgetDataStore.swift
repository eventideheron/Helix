import Foundation

struct HelixWidgetDataStore {

    private static let suiteName = "group.com.joshlang.helix"
    private static let recordKey = "helix.widget.record"

    static func save(_ record: HelixWidgetDisplayRecord) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: recordKey)
    }

    static func load() -> HelixWidgetDisplayRecord? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: recordKey),
              let record = try? JSONDecoder().decode(HelixWidgetDisplayRecord.self, from: data)
        else { return nil }
        return record
    }
}
