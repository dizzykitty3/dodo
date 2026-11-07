import Foundation
import SwiftData

enum RepeatRule: String, CaseIterable {
    case never = "Never", daily = "Daily", weekdays = "Weekdays", weekly = "Weekly", monthly = "Monthly"
}

struct Subtask: Codable, Identifiable {
    var id = UUID()
    var title = ""
    var isComplete = false
}

@Model
final class TaskRecord {
    var title: String
    var createdAt = Date.now
    // Store a calendar day independently of time zone and daylight saving changes.
    var dueDay: String?
    var repeatRule = RepeatRule.never.rawValue
    var repeatDay: Int?
    var isUrgent = false
    var isPersonal = false
    var completedAt: Date?
    var occurrenceKey: UUID?
    var successorKey: UUID?
    var deletedAt: Date?
    var countedCompletion = false
    var group: TaskGroup?
    var subtasks: [Subtask] = []

    init(title: String) { self.title = title }

    static var dayFormat: Date.VerbatimFormatStyle {
        .init(format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)",
              locale: Locale(identifier: "en_US_POSIX"), timeZone: .current,
              calendar: Calendar(identifier: .gregorian))
    }
}

@Model
final class TaskGroup {
    var name: String
    var createdAt = Date.now
    init(name: String) { self.name = name }
}
