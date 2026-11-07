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
        #expect(task.subtasks.first?.isComplete == true)
        task.title = "Review"
        task.subtasks = []
        try store.mainContext.save()
    }
    do {
        let store = try openStore()
        let task = try #require(store.mainContext.fetch(FetchDescriptor<TaskRecord>()).first)
        #expect(task.title == "Review" && task.subtasks.isEmpty)
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
        try CompletedTaskCleanup.purge([task, recent], interval: interval, now: now, context: context)
        #expect(try context.fetchCount(FetchDescriptor<TaskRecord>()) == 2)
    }
    CompletedTaskCleanup.scheduleNext(after: task, context: context)
    try CompletedTaskCleanup.purge([task, recent], interval: .oneDay, now: now, context: context)
    let remaining = try context.fetch(FetchDescriptor<TaskRecord>())
    #expect(remaining.count == 2)
    let next = try #require(remaining.first { $0.title == "Weekly review" })
    #expect(next.completedAt == nil && next.repeatDay == 2 && next.subtasks.first?.isComplete == false)
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
