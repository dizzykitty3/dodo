import SwiftUI
import SwiftData

@main
struct DODOApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: TaskRecord.self)
    }
}
