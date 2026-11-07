import SwiftUI
import SwiftData

@main
struct DODOApp: App {
    init() {
        DateBadgePreferences.initializeFromSystem()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [TaskRecord.self, CompletionArchive.self])
    }
}
