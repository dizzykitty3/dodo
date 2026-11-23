import Foundation
import SwiftData

enum RepeatRule: String, CaseIterable {
    case never = "Never", daily = "Daily", weekdays = "Weekdays", weekends = "Weekends"
    case weekly = "Weekly", biweekly = "Every Two Weeks", monthly = "Monthly", yearly = "Yearly", custom = "Custom"
}

struct Subtask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var isComplete = false {
        didSet { if isComplete != oldValue { completedAt = isComplete ? .now : nil } }
    }
    var completedAt: Date?
}

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
    @Relationship(originalName: "group") var list: TaskListRecord?
    @Attribute(originalName: "sectionID") var tagID: UUID?
    var subtasks: [Subtask] = []

    init(title: String) { self.title = title }

    // Older versions allowed completing a parent with unfinished subtasks.
    var displayedSubtasks: [Subtask] {
        guard completedAt != nil else { return subtasks }
        return subtasks.map { child in
            var child = child
            child.isComplete = true
            return child
        }
    }

    @MainActor
    func syncSubtaskCompletion(in context: ModelContext) throws {
        guard !subtasks.isEmpty else { return }
        try setCompleted(subtasks.allSatisfy(\.isComplete), in: context)
    }

    @MainActor
    func setCompleted(_ done: Bool, in context: ModelContext) throws {
        guard done != (completedAt != nil) else { return }
        completedAt = done ? .now : nil
        if done {
            countedCompletion = true
            CompletedTaskCleanup.scheduleNext(after: self, context: context)
        } else {
            try CompletedTaskCleanup.withdrawNext(after: self, context: context)
        }
    }

    static var dayFormat: Date.VerbatimFormatStyle {
        .init(format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)",
              locale: Locale(identifier: "en_US_POSIX"), timeZone: .current,
              calendar: Calendar(identifier: .gregorian))
    }
}

struct TaskListSection: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
}

@Model
final class TaskGroup {
    var name: String
    var createdAt = Date.now
    @Attribute(originalName: "sections") var tags: [TaskTag] = []
    var colorName = "Indigo"
    var symbolName = "list.bullet"
    var position = 0
    static var displayOrder: [SortDescriptor<TaskListRecord>] {
        [SortDescriptor(\TaskListRecord.position), SortDescriptor(\TaskListRecord.createdAt)]
    }

    func applyTagEdits(_ draft: [TaskTag], originalIDs: Set<UUID>, in context: ModelContext) throws {
        let currentIDs = Set(tags.map(\.id))
        let removed = originalIDs.subtracting(draft.map(\.id))
        let concurrentAdditions = tags.filter { !originalIDs.contains($0.id) }
        let ordered = draft.filter { !originalIDs.contains($0.id) || currentIDs.contains($0.id) }
        if !removed.isEmpty {
            let id = persistentModelID
            let members = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.list?.persistentModelID == id })
            for task in try context.fetch(members) {
                if let tagID = task.tagID, removed.contains(tagID) { task.tagID = nil }
            }
        }
        tags = ordered + concurrentAdditions
    }

    func deleteKeepingTasks(in context: ModelContext) throws {
        let id = persistentModelID
        let members = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.list?.persistentModelID == id })
        for task in try context.fetch(members) {
            task.tagID = nil
            task.list = nil
        }
        context.delete(self)
    }

    init(name: String, position: Int = 0) {
        self.name = name
        self.position = position
    }
}

// Legacy storage type names remain stable; application code uses list/tag terminology.
typealias TaskListRecord = TaskGroup
typealias TaskTag = TaskListSection
