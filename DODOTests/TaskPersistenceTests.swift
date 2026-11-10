import Foundation
import SwiftData
import Testing
@testable import DODO

@MainActor
@Test func taskSurvivesReopeningAndCanBeEditedAndDeleted() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let configuration = ModelConfiguration(url: directory.appending(path: "Tasks.store"))
    func openStore() throws -> ModelContainer {
        try ModelContainer(for: TaskRecord.self, configurations: configuration)
    }

    do {
        let store = try openStore()
        let task = TaskRecord(title: "Weekly review")
        let list = TaskGroup(name: "Projects")
        let section = TaskListSection(name: "Planning")
        list.sections = [section]
        store.mainContext.insert(list)
        task.group = list
        task.sectionID = section.id
        task.link = URL(string: "https://example.com/review")
        task.dueDay = "2026-11-09"
        task.repeatRule = RepeatRule.weekly.rawValue
        task.repeatDay = 2
        task.isUrgent = true
        task.subtasks = [Subtask(title: "Read notes", isComplete: true)]
        store.mainContext.insert(task)
        try store.mainContext.save()
    }
    do {
        let store = try openStore()
        let task = try #require(store.mainContext.fetch(FetchDescriptor<TaskRecord>()).first)
        #expect(task.dueDay == "2026-11-09" && task.isUrgent && task.repeatDay == 2)
        #expect(task.link?.absoluteString == "https://example.com/review")
        #expect(task.subtasks.first?.isComplete == true)
        let list = try #require(task.group)
        let section = try #require(list.sections.first)
        #expect(section.name == "Planning" && task.sectionID == section.id)
        try list.deleteKeepingTasks(in: store.mainContext)
        task.link = nil
        task.title = "Review"
        task.subtasks = []
        try store.mainContext.save()
    }
    do {
        let store = try openStore()
        let task = try #require(store.mainContext.fetch(FetchDescriptor<TaskRecord>()).first)
        #expect(task.title == "Review" && task.subtasks.isEmpty && task.link == nil)
        #expect(task.group == nil && task.sectionID == nil)
        store.mainContext.delete(task)
        try store.mainContext.save()
    }
    let store = try openStore()
    #expect(try store.mainContext.fetchCount(FetchDescriptor<TaskRecord>()) == 0)
}

@MainActor
@Test func cleanupUsesCompletionTimeAndKeepsTheNextOccurrence() throws {
    let container = try ModelContainer(for: TaskRecord.self, CompletionArchive.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let now = Date.now
    let task = TaskRecord(title: "Weekly review")
    task.completedAt = now.addingTimeInterval(-86_400)
    task.repeatRule = RepeatRule.weekly.rawValue
    task.repeatDay = 2
    task.countedCompletion = true
    task.subtasks = [Subtask(title: "Review notes", isComplete: true)]
    let recent = TaskRecord(title: "Recent")
    recent.completedAt = now.addingTimeInterval(-86_399)
    recent.dueDay = "2020-01-01"
    context.insert(task)
    context.insert(recent)
    try context.save()
    for interval in [CleanupInterval.never, .sevenDays] {
        try CompletedTaskCleanup.apply([task, recent], policy: CleanupPolicy(clear: interval, delete: .sevenDays), now: now, context: context)
        #expect(try context.fetchCount(FetchDescriptor<TaskRecord>()) == 2)
    }
    CompletedTaskCleanup.scheduleNext(after: task, context: context)
    try CompletedTaskCleanup.apply([task, recent], policy: CleanupPolicy(clear: .oneDay, delete: .sevenDays), now: now, context: context)
    #expect(task.deletedAt == now)
    #expect(recent.deletedAt == nil)
    #expect(try context.fetchCount(FetchDescriptor<TaskRecord>()) == 3)
    for (retention, elapsed) in [(TrashRetention.never, 60 * 86_400), (.sevenDays, 7 * 86_400 - 1)] {
        try CompletedTaskCleanup.apply([task], policy: CleanupPolicy(clear: .never, delete: retention),
                                       now: now.addingTimeInterval(Double(elapsed)), context: context)
        #expect(try context.fetchCount(FetchDescriptor<TaskRecord>()) == 3)
    }
    try CompletedTaskCleanup.apply([task], policy: CleanupPolicy(clear: .never, delete: .sevenDays),
                                   now: now.addingTimeInterval(7 * 86_400), context: context)
    let remaining = try context.fetch(FetchDescriptor<TaskRecord>())
    #expect(remaining.count == 2)
    let next = try #require(remaining.first { $0.title == "Weekly review" })
    #expect(next.completedAt == nil && next.repeatDay == nil && next.subtasks.first?.isComplete == false)
    #expect(try context.fetch(FetchDescriptor<CompletionArchive>()).first?.count == 1)
}

@MainActor
@Test func subtasksDriveCompletionAndLateRestoreWithdrawsSuccessor() throws {
    let store = try ModelContainer(for: TaskRecord.self, CompletionArchive.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = store.mainContext
    let task = TaskRecord(title: "Daily checklist")
    task.repeatRule = RepeatRule.daily.rawValue
    task.subtasks = [Subtask(title: "First", isComplete: true), Subtask(title: "Second")]
    context.insert(task)
    try task.syncSubtaskCompletion(in: context)
    #expect(task.completedAt == nil)
    task.subtasks[1].isComplete = true
    try task.syncSubtaskCompletion(in: context)
    try context.save()
    #expect(task.completedAt != nil && task.successorKey != nil)
    #expect(try context.fetchCount(FetchDescriptor<TaskRecord>()) == 2)

    task.completedAt = Date.now.addingTimeInterval(-86_400)
    task.subtasks[0].isComplete = false
    try task.syncSubtaskCompletion(in: context)
    try context.save()
    #expect(task.completedAt == nil && task.successorKey == nil && task.countedCompletion)
    #expect(try context.fetchCount(FetchDescriptor<TaskRecord>()) == 1)
}

@MainActor
@Test func weekendAndCustomRepeatsFollowSelectedDays() throws {
    let store = try ModelContainer(for: TaskRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = store.mainContext
    for (rule, days, completion, expected) in [
        (RepeatRule.weekends, [], "2026-11-06", "2026-11-07"),
        (.weekends, [], "2026-11-07", "2026-11-08"),
        (.weekends, [], "2026-11-08", "2026-11-14"),
        (.custom, [1, 3], "2026-11-08", "2026-11-10"),
        (.custom, [1, 3], "2026-11-10", "2026-11-15")
    ] {
        let task = TaskRecord(title: "Practice")
        task.repeatRule = rule.rawValue
        task.repeatWeekdays = days
        task.completedAt = try TaskRecord.dayFormat.parseStrategy.parse(completion)
        context.insert(task)
        CompletedTaskCleanup.scheduleNext(after: task, context: context)
        try context.save()
        let key = try #require(task.successorKey)
        let successor = try #require(context.fetch(FetchDescriptor<TaskRecord>()).first { $0.occurrenceKey == key })
        #expect(successor.dueDay == expected && successor.repeatWeekdays == days && successor.repeatRule == rule.rawValue)
    }
}

@MainActor
@Test func editingGroupsReordersSurvivorsAndUngroupsOnlyAffectedTasks() throws {
    let store = try ModelContainer(for: TaskRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = store.mainContext
    let list = TaskGroup(name: "Work")
    let sections = ["Inbox", "Planning", "Later"].map { TaskListSection(name: $0) }
    list.sections = sections
    context.insert(list)
    let tasks = sections.map { section in
        let task = TaskRecord(title: section.name)
        task.group = list
        task.sectionID = section.id
        context.insert(task)
        return task
    }
    tasks[0].completedAt = .now
    try context.save()
    try list.applySectionEdits([sections[2], sections[1]], originalIDs: Set(sections.map(\.id)), in: context)
    try context.save()
    #expect(list.sections.map(\.id) == [sections[2].id, sections[1].id])
    #expect(try context.fetchCount(FetchDescriptor<TaskRecord>()) == 3)
    #expect(tasks[0].sectionID == nil && tasks[0].group == list && tasks[0].completedAt != nil)
    #expect(tasks[1].sectionID == sections[1].id && tasks[2].sectionID == sections[2].id)
}

@MainActor
@Test func weeklyRepeatFollowsDueDateEvenWhenCompletedLate() throws {
    let store = try ModelContainer(for: TaskRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    for (due, expected) in [("2026-11-10", "2026-11-17"), ("2026-11-11", "2026-11-18")] {
        let record = TaskRecord(title: "Weekly")
        record.dueDay = due
        record.repeatRule = RepeatRule.weekly.rawValue
        record.repeatDay = 2 // Previously selected Monday.
        record.completedAt = try TaskRecord.dayFormat.parseStrategy.parse("2026-11-13")
        store.mainContext.insert(record)
        CompletedTaskCleanup.scheduleNext(after: record, context: store.mainContext)
        let key = try #require(record.successorKey)
        let next = try #require(store.mainContext.fetch(FetchDescriptor<TaskRecord>()).first { $0.occurrenceKey == key })
        #expect(next.dueDay == expected)
    }
}
