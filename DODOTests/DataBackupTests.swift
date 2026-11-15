import Foundation
import SwiftData
import Testing
@testable import DODO

@MainActor
private func backupStore() throws -> ModelContainer {
    try ModelContainer(for: TaskRecord.self, CompletionArchive.self,
                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
}

@MainActor
@Test func backupRoundTripReplacesAllDataAndPreferences() throws {
    let suite = "dodo-backup-tests-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(2, forKey: "todayPreviewLimit")
    defaults.set("dd/MM/yyyy", forKey: "dateBadgeInitialPattern")
    defaults.set(true, forKey: "dateBadgeInitialized")
    defaults.set("Day, Month, Year", forKey: "dateBadgeInitialOrder")
    defaults.set("/", forKey: "dateBadgeInitialSeparator")
    let source = try backupStore()
    let list = TaskGroup(name: "Work", position: 3)
    list.colorName = "Teal"
    list.symbolName = "briefcase.fill"
    let group = TaskListSection(name: "Planning")
    list.sections = [group, TaskListSection(name: "Empty group")]
    source.mainContext.insert(list)
    source.mainContext.insert(TaskGroup(name: "Empty list"))
    let task = TaskRecord(title: "Review")
    task.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    task.link = URL(string: "https://example.com")
    task.dueDay = "2026-11-15"
    task.repeatRule = RepeatRule.custom.rawValue
    task.repeatWeekdays = [1, 3, 7]
    task.isUrgent = true
    task.isPersonal = true
    task.completedAt = task.createdAt
    task.deletedAt = task.createdAt
    task.restoredCompletion = task.createdAt
    task.countedCompletion = true
    task.group = list
    task.sectionID = group.id
    task.subtasks = [Subtask(title: "Read", isComplete: true)]
    source.mainContext.insert(task)
    source.mainContext.insert(CompletionArchive(count: 8))
    try source.mainContext.save()
    let data = try BackupStore.snapshot(context: source.mainContext, defaults: defaults).encoded()
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["format"] as? String == "dodo")
    #expect(json["schemaVersion"] as? String == "v1")
    let backup = try DODOBackup.decode(data)

    let destination = try backupStore()
    destination.mainContext.insert(TaskRecord(title: "Local task"))
    destination.mainContext.insert(TaskGroup(name: "Local list"))
    destination.mainContext.insert(CompletionArchive(count: 99))
    defaults.set(5, forKey: "todayPreviewLimit")
    defaults.set(true, forKey: "dateBadgeAbbreviatesMonth")
    try BackupStore.apply(backup, mode: .replace, context: destination.mainContext, defaults: defaults)
    let tasks = try destination.mainContext.fetch(FetchDescriptor<TaskRecord>())
    let restored = try #require(tasks.first)
    #expect(tasks.count == 1 && restored.title == "Review")
    #expect(restored.link == task.link && restored.createdAt == task.createdAt)
    #expect(restored.completedAt == task.completedAt && restored.deletedAt == task.deletedAt)
    #expect(restored.restoredCompletion == task.restoredCompletion && restored.countedCompletion)
    #expect(restored.isUrgent && restored.isPersonal && restored.dueDay == task.dueDay)
    #expect(restored.repeatRule == task.repeatRule && restored.repeatWeekdays == [1, 3, 7])
    #expect(restored.group?.name == "Work" && restored.group?.colorName == "Teal")
    #expect(restored.group?.symbolName == "briefcase.fill" && restored.sectionID == group.id)
    #expect(restored.subtasks == task.subtasks && restored.group?.sections.count == 2)
    #expect(try destination.mainContext.fetchCount(FetchDescriptor<TaskGroup>()) == 2)
    #expect(try destination.mainContext.fetch(FetchDescriptor<CompletionArchive>()).map(\.count) == [8])
    #expect(defaults.integer(forKey: "todayPreviewLimit") == 2)
    #expect(!defaults.bool(forKey: "dateBadgeAbbreviatesMonth"))
    #expect(defaults.string(forKey: "dateBadgeInitialPattern") == "dd/MM/yyyy")
}

@MainActor
@Test func mergeReusesNamedListsAndGroupsAndIsolatesRepeatGraph() throws {
    let suite = "dodo-merge-tests-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let source = try backupStore()
    let list = TaskGroup(name: "work")
    list.sections = [TaskListSection(name: "planning"), TaskListSection(name: "Later")]
    source.mainContext.insert(list)
    let completed = TaskRecord(title: "Repeat")
    completed.group = list
    completed.sectionID = list.sections[0].id
    completed.dueDay = "2026-11-15"
    completed.repeatRule = RepeatRule.daily.rawValue
    completed.subtasks = [Subtask(title: "Step", isComplete: true)]
    source.mainContext.insert(completed)
    try completed.setCompleted(true, in: source.mainContext)
    source.mainContext.insert(CompletionArchive(count: 4))
    let backup = try BackupStore.snapshot(context: source.mainContext, defaults: defaults)

    let destination = try backupStore()
    let existing = TaskGroup(name: " Work ", position: 20)
    existing.colorName = "Rose"
    let existingGroup = TaskListSection(name: "Planning")
    existing.sections = [existingGroup]
    destination.mainContext.insert(existing)
    let local = TaskRecord(title: "Local")
    // Deliberately share a key with the backup to check that imported undo cannot delete local tasks.
    local.occurrenceKey = completed.successorKey
    destination.mainContext.insert(local)
    defaults.set(0, forKey: "todayPreviewLimit")
    try BackupStore.apply(backup, mode: .merge, context: destination.mainContext, defaults: defaults)
    #expect(defaults.integer(forKey: "todayPreviewLimit") == 0)
    #expect(try destination.mainContext.fetchCount(FetchDescriptor<TaskGroup>()) == 1)
    #expect(existing.colorName == "Rose" && existing.sections.count == 2)
    let tasks = try destination.mainContext.fetch(FetchDescriptor<TaskRecord>())
    #expect(tasks.count == 3)
    let imported = try #require(tasks.first { $0.completedAt != nil })
    #expect(imported.group === existing && imported.sectionID == existingGroup.id)
    #expect(imported.successorKey != completed.successorKey)
    #expect(imported.subtasks[0].id != completed.subtasks[0].id)
    try imported.setCompleted(false, in: destination.mainContext)
    try destination.mainContext.save()
    #expect(try destination.mainContext.fetchCount(FetchDescriptor<TaskRecord>()) == 2)
    #expect(try destination.mainContext.fetch(FetchDescriptor<TaskRecord>()).contains { $0.title == "Local" })
    // Re-import appends tasks again, but does not duplicate the same named groups.
    try BackupStore.apply(backup, mode: .merge, context: destination.mainContext, defaults: defaults)
    #expect(try destination.mainContext.fetchCount(FetchDescriptor<TaskRecord>()) == 4)
    #expect(existing.sections.count == 2)
}

@MainActor
@Test func invalidBackupCannotReplaceLocalData() throws {
    let suite = "dodo-invalid-tests-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let container = try backupStore()
    container.mainContext.insert(TaskRecord(title: "Keep me"))
    defaults.set(1, forKey: "todayPreviewLimit")
    var backup = try BackupStore.snapshot(context: container.mainContext, defaults: defaults)
    backup.tasks[0].listID = UUID()
    #expect(throws: (any Error).self) {
        try BackupStore.apply(backup, mode: .replace, context: container.mainContext, defaults: defaults)
    }
    #expect(try container.mainContext.fetch(FetchDescriptor<TaskRecord>()).map(\.title) == ["Keep me"])
    #expect(defaults.integer(forKey: "todayPreviewLimit") == 1)
    #expect(throws: (any Error).self) { try DODOBackup.decode(Data("{}".utf8)) }
    #expect(throws: (any Error).self) { try DODOBackup.decode(Data(#"{"format":"other","schemaVersion":"v1"}"#.utf8)) }
    #expect(throws: (any Error).self) { try DODOBackup.decode(Data(#"{"format":"dodo","schemaVersion":"v2"}"#.utf8)) }
    backup.tasks[0].listID = nil
    let key = UUID()
    backup.tasks[0].occurrenceKey = key
    backup.tasks[0].successorKey = key
    #expect(throws: (any Error).self) { try backup.validate() }
}

@MainActor
@Test func replacingWithEmptyBackupClearsEverything() throws {
    let suite = "dodo-empty-tests-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let container = try backupStore()
    container.mainContext.insert(TaskRecord(title: "Delete me"))
    container.mainContext.insert(TaskGroup(name: "Delete list"))
    container.mainContext.insert(CompletionArchive(count: 2))
    let empty = DODOBackup(preferences: BackupPreferences(defaults: defaults), archivedCompletedCount: 0, lists: [], tasks: [])
    try BackupStore.apply(empty, mode: .replace, context: container.mainContext, defaults: defaults)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<TaskRecord>()) == 0)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<TaskGroup>()) == 0)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<CompletionArchive>()) == 0)
}
