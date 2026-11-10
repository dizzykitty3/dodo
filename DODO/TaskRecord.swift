import Foundation
import SwiftData

enum RepeatRule: String, CaseIterable {
    case never = "Never", daily = "Daily", weekdays = "Weekdays", weekends = "Weekends"
    case weekly = "Weekly", monthly = "Monthly", custom = "Custom"
}

struct Subtask: Codable, Identifiable {
    var id = UUID()
    var title = ""
    var isComplete = false
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
    var group: TaskGroup?
    var sectionID: UUID?
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

struct TaskListSection: Identifiable, Codable {
    var id = UUID()
    var name: String
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

    func deleteKeepingTasks(in context: ModelContext) throws {
        let id = persistentModelID
        let members = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.group?.persistentModelID == id })
        for task in try context.fetch(members) {
            task.sectionID = nil
            task.group = nil
        }
        context.delete(self)
    }

    init(name: String, position: Int = 0) {
        self.name = name
        self.position = position
    }
}
