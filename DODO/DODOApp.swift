import SwiftUI
import SwiftData

@main
struct DODOApp: App {
    init() {
        DateBadgePreferences.initializeFromSystem()
    }

    private var isolatedStore: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-test-in-memory")
        #else
        false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [TaskRecord.self, CompletionArchive.self], inMemory: isolatedStore)
    }
}
