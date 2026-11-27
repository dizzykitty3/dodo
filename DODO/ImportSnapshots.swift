import Foundation
import SwiftData

@MainActor
struct ImportSnapshots {
    struct Entry: Identifiable {
        let id: URL
        let date: Date
        let taskCount: Int?
    }

    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory
            .appending(path: "DODO/ImportSnapshots", directoryHint: .isDirectory)
    }

    func entries() throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.pathExtension == "json" }
            .map { url in
                // Damaged snapshots stay visible so users can still delete them.
                let backup = try? load(url)
                let date = backup?.exportedAt ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return Entry(id: url, date: date, taskCount: backup?.tasks.count)
            }
            .sorted { $0.date > $1.date }
    }

    @discardableResult
    func capture(context: ModelContext, defaults: UserDefaults = .standard) throws -> URL {
        try context.save()
        let data = try BackupStore.snapshot(context: context, defaults: defaults).encoded()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(UUID().uuidString).json")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    func load(_ url: URL) throws -> DODOBackup {
        try DODOBackup.decode(Data(contentsOf: url))
    }

    func delete(_ entry: Entry) throws {
        try FileManager.default.removeItem(at: entry.id)
    }

    func importData(_ backup: DODOBackup, mode: BackupStore.ImportMode,
                    context: ModelContext, defaults: UserDefaults = .standard) throws {
        try backup.validate()
        // A snapshot must reach disk before any import mutation is allowed.
        try capture(context: context, defaults: defaults)
        try BackupStore.apply(backup, mode: mode, context: context, defaults: defaults)
    }

    func restore(_ entry: Entry, context: ModelContext, defaults: UserDefaults = .standard) throws {
        let backup = try load(entry.id)
        // Keep the current state too, making an accidental restore recoverable.
        try importData(backup, mode: .replace, context: context, defaults: defaults)
    }
}
