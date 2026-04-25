// App/HelixApp.swift

import SwiftUI
import SwiftData

@main
struct HelixApp: SwiftUI.App {
    var body: some Scene {
        WindowGroup {
            HelixContentView()
        }
        .modelContainer(makeSharedModelContainer())
    }
}
