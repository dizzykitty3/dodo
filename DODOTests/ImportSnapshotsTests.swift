import Foundation
import SwiftData
import Testing
@testable import DODO

@MainActor
@Test func importSnapshotsRestoreDataSettingsAndSubtaskTimes() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let suite = "snapshot-test-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let container = try ModelContainer(for: TaskRecord.self, CompletionArchive.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let original = TaskRecord(title: "Original")
    original.subtasks = [Subtask(title: "Finished", isComplete: true, completedAt: date)]
    original.deletedAt = date
    let list = TaskListRecord(name: "Work")
    list.tags = [TaskTag(name: "Planning")]
    context.insert(list)
    original.list = list
    original.tagID = list.tags[0].id
    context.insert(original)
    context.insert(CompletionArchive(count: 7))
    defaults.set(2, forKey: "todayPreviewLimit")
    try context.save()
    var incoming = try BackupStore.snapshot(context: context, defaults: defaults)
    incoming.tasks[0].title = "Imported"
    incoming.preferences.todayPreviewLimit = 5
    let store = ImportSnapshots(directory: root)
    try store.importData(incoming, mode: .replace, context: context, defaults: defaults)
    let beforeImport = try #require(store.entries().first)
    #expect(beforeImport.taskCount == 1)
    #expect(defaults.integer(forKey: "todayPreviewLimit") == 5)
    #expect(try context.fetch(FetchDescriptor<TaskRecord>()).first?.title == "Imported")
    #expect(try context.fetch(FetchDescriptor<TaskRecord>()).first?.subtasks.first?.completedAt == date)
    try store.restore(beforeImport, context: context, defaults: defaults)
    #expect(try store.entries().count == 2)
    let restored = try #require(context.fetch(FetchDescriptor<TaskRecord>()).first)
    #expect(restored.title == "Original")
    #expect(restored.deletedAt == date)
    #expect(restored.subtasks.first?.completedAt == date)
    #expect(restored.list?.tags.first?.id == restored.tagID)
    #expect(defaults.integer(forKey: "todayPreviewLimit") == 2)
    #expect(try context.fetch(FetchDescriptor<CompletionArchive>()).first?.count == 7)
    try store.importData(incoming, mode: .merge, context: context, defaults: defaults)
    #expect(try store.entries().count == 3)
    #expect(try context.fetchCount(FetchDescriptor<TaskRecord>()) == 2)
    #expect(defaults.integer(forKey: "todayPreviewLimit") == 2)
    try store.delete(beforeImport)
    #expect(try store.entries().count == 2)
    #expect(try context.fetchCount(FetchDescriptor<TaskRecord>()) == 2)

    let blocked = root.appending(path: "not-a-directory")
    try Data().write(to: blocked)
    do {
        try ImportSnapshots(directory: blocked).importData(incoming, mode: .replace, context: context, defaults: defaults)
        Issue.record("Import must stop when its snapshot cannot be saved")
    } catch {
        #expect(try context.fetchCount(FetchDescriptor<TaskRecord>()) == 2)
        #expect(defaults.integer(forKey: "todayPreviewLimit") == 2)
    }
}
