import Foundation
import SwiftData
import Testing
@testable import DODO

@MainActor
@Test func emptyCleanupPreservesAllTaskStates() throws {
    let store = try ModelContainer(for: TaskRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = store.mainContext
    let empty = TaskListRecord(name: "Empty")
    empty.tags = [TaskTag(name: "Empty tag")]
    context.insert(empty)
    let occupied = TaskListRecord(name: "Occupied")
    occupied.tags = [TaskTag(name: "Active"), TaskTag(name: "Completed"), TaskTag(name: "Deleted"), TaskTag(name: "Empty")]
    context.insert(occupied)
    for index in 0..<3 {
        let task = TaskRecord(title: "Task \(index)")
        task.list = occupied
        task.tagID = occupied.tags[index].id
        if index == 1 { task.completedAt = .now }
        if index == 2 { task.deletedAt = .now }
        context.insert(task)
    }
    try context.save()
    let candidates = EmptyListCleanup.candidates(lists: [empty, occupied], tasks: try context.fetch(FetchDescriptor<TaskRecord>()))
    #expect(candidates.lists.count == 1)
    #expect(candidates.tagCount == 2)
    try EmptyListCleanup.delete(in: context)
    #expect(try context.fetchCount(FetchDescriptor<TaskListRecord>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<TaskRecord>()) == 3)
    #expect(occupied.tags.map(\.name) == ["Active", "Completed", "Deleted"])
    try EmptyListCleanup.delete(in: context)
    #expect(try context.fetchCount(FetchDescriptor<TaskRecord>()) == 3)
}
