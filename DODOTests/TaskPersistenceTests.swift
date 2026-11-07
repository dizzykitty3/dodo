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
