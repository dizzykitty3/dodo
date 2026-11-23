import Foundation
import SwiftData

@MainActor
enum EmptyListCleanup {
    struct Candidates {
        var lists: [TaskListRecord]
        var tags: [(list: TaskListRecord, ids: Set<UUID>)]
        var tagCount: Int { tags.reduce(0) { $0 + $1.ids.count } + lists.reduce(0) { $0 + $1.tags.count } }
        var isEmpty: Bool { lists.isEmpty && tags.isEmpty }
    }

    static func candidates(lists: [TaskListRecord], tasks: [TaskRecord]) -> Candidates {
        let members = Dictionary(grouping: tasks.compactMap { task in
            task.list.map { ($0.persistentModelID, task.tagID) }
        }, by: { $0.0 })
        var result = Candidates(lists: [], tags: [])
        for list in lists {
            let tasks = members[list.persistentModelID] ?? []
            if tasks.isEmpty {
                result.lists.append(list)
            } else {
                let occupied = Set(tasks.compactMap { $0.1 })
                let empty = Set(list.tags.map(\.id)).subtracting(occupied)
                if !empty.isEmpty { result.tags.append((list, empty)) }
            }
        }
        return result
    }

    static func delete(in context: ModelContext) throws {
        // Recheck all records at confirmation time, including completed and deleted tasks.
        let lists = try context.fetch(FetchDescriptor<TaskListRecord>())
        let tasks = try context.fetch(FetchDescriptor<TaskRecord>())
        let empty = candidates(lists: lists, tasks: tasks)
        do {
            for entry in empty.tags { entry.list.tags.removeAll { entry.ids.contains($0.id) } }
            for list in empty.lists { context.delete(list) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
