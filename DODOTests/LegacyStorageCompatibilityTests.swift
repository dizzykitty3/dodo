import Foundation
import SwiftData
import Testing
@testable import DODO

private enum LegacyStoreV1 {
@Model
final class TaskRecord {
    var title: String
    var link: URL?
    var createdAt = Date.now
    // Store a calendar day independently of time zone and daylight saving changes.
    var dueDay: String?
    var repeatRule = RepeatRule.never.rawValue
    var repeatDay: Int?
    var repeatWeekdays: [Int] = []
    var isUrgent = false
    var isPersonal = false
    var completedAt: Date?
    var occurrenceKey: UUID?
    var successorKey: UUID?
    var deletedAt: Date?
    var restoredCompletion: Date?
    var countedCompletion = false
    var group: TaskGroup?
    var sectionID: UUID?
    var subtasks: [Subtask] = []

    init(title: String) { self.title = title }

}
@Model
final class TaskGroup {
    var name: String
    var createdAt = Date.now
    var sections: [TaskListSection] = []
    var colorName = "Indigo"
    var symbolName = "list.bullet"
    var position = 0
    static var displayOrder: [SortDescriptor<TaskGroup>] {
        [SortDescriptor(\TaskGroup.position), SortDescriptor(\TaskGroup.createdAt)]
    }

    init(name: String) { self.name = name }
}
}

@MainActor
@Test func legacyStorePreservesListsAndTagsAfterRenaming() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let config = ModelConfiguration(url: directory.appending(path: "Tasks.store"))
    let tagID = UUID()
    do {
        let old = try ModelContainer(for: LegacyStoreV1.TaskRecord.self, configurations: config)
        let list = LegacyStoreV1.TaskGroup(name: "Projects")
        list.sections = [TaskListSection(id: tagID, name: "Planning")]
        let task = LegacyStoreV1.TaskRecord(title: "Keep my task")
        task.group = list
        task.sectionID = tagID
        old.mainContext.insert(task)
        try old.mainContext.save()
    }
    let current = try ModelContainer(for: DODO.TaskRecord.self, configurations: config)
    let task = try #require(current.mainContext.fetch(FetchDescriptor<DODO.TaskRecord>()).first)
    #expect(task.title == "Keep my task")
    #expect(task.list?.name == "Projects")
    #expect(task.tagID == tagID && task.list?.tags.first?.id == tagID)
    #expect(task.list?.tags.first?.name == "Planning")
}
