// Data/Persistence/ModelContainerFactory.swift
// Owns SwiftData container creation and App Group configuration.
// ChatGPT recommendation: SwiftData + app group storage deserves its own home,
// not mixed into domain model files.
//
// IMPORTANT: Update helixAppGroupID to match your Xcode entitlement before first build.
// Both the main app target and HelixWidgetExtension target must share this identifier.

import SwiftData
import Foundation

// MARK: — App Group identifier
// Edit this string to match your Apple Developer App Group entitlement.
// Format: group.com.YOURNAME.helix
let helixAppGroupID = "group.com.joshlang.helix"

// MARK: — Shared store URL
// Widget and app both read/write from this location via the App Group container.
// When the process has no App Group entitlement (e.g. some simulator test runs),
// fall back to Application Support so the test host can bootstrap.
var helixSharedStoreURL: URL {
    if let groupURL = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: helixAppGroupID) {
        return groupURL.appendingPathComponent("helix.store")
    }
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("Helix/helix.store")
}

// MARK: — Container factory

struct ModelContainerFactory {

    /// Creates the shared SwiftData container used by both app and widget targets.
    ///
    /// Recovery: open on disk → on failure delete store + SQLite sidecars (`-wal`, `-shm`) and retry once →
    /// on second failure use in-memory store so the app can launch. **`fatalError`** only if in-memory creation fails.
    static func makeSharedContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: HelixSchemaV2.self)
        let storeURL = helixSharedStoreURL

        func openWithMigration() throws -> ModelContainer {
            let config = ModelConfiguration(url: storeURL)
            return try ModelContainer(
                for: schema,
                migrationPlan: HelixMigrationPlan.self,
                configurations: config
            )
        }

        // Attempt 1 — open with migration plan
        do {
            let container = try openWithMigration()
            print("[Helix] SwiftData container opened successfully at \(storeURL.path)")
            return container
        } catch {
            print("[Helix] SwiftData open failed (attempt 1): \(error.localizedDescription)")
        }

        // Attempt 2 — wipe store, retry with migration plan
        print("[Helix] Attempting store recovery: deleting existing store files.")
        deleteStoreFiles(at: storeURL)

        do {
            let container = try openWithMigration()
            print("[Helix] SwiftData container recovered successfully (store was reset).")
            return container
        } catch {
            print("[Helix] SwiftData open failed after store reset (attempt 2): \(error.localizedDescription)")
        }

        // Attempt 3 — in-memory fallback (last resort only)
        print("[Helix] WARNING: Falling back to in-memory container. Data will not persist.")
        let fallbackConfig = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: fallbackConfig)
        } catch {
            fatalError("[Helix] FATAL: In-memory container creation failed. Schema is malformed: \(error.localizedDescription)")
        }
    }

    /// Removes the primary SQLite store file and WAL/SHM sidecars for `storeURL` (e.g. `helix.store`, `helix.store-wal`, `helix.store-shm`).
    private static func deleteStoreFiles(at storeURL: URL) {
        let fm = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        let baseName = storeURL.lastPathComponent
        let companionNames = ["\(baseName)-wal", "\(baseName)-shm"]
        let urls = [storeURL] + companionNames.map { directory.appendingPathComponent($0) }

        for url in urls {
            guard fm.fileExists(atPath: url.path) else { continue }
            do {
                try fm.removeItem(at: url)
                print("[Helix] Removed store file: \(url.lastPathComponent)")
            } catch {
                print("[Helix] Warning: could not remove \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    /// Creates an in-memory container for SwiftUI previews and unit tests.
    /// Data does not persist between runs.
    static func makePreviewContainer() -> ModelContainer {
        let schema = Schema([
            HelixDailyRecord.self,
            HelixBaselineSnapshot.self,
            HelixTriggerRecord.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: config)
    }
}

// Convenience alias used in HelixApp.swift
func makeSharedModelContainer() -> ModelContainer {
    ModelContainerFactory.makeSharedContainer()
}
