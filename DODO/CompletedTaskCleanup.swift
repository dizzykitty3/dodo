import Foundation
import SwiftData

enum CleanupInterval: Int, CaseIterable {
    case never = 0, oneDay = 1, sevenDays = 7

    func deadline(for completion: Date) -> Date? {
        self == .never ? nil : completion.addingTimeInterval(Double(rawValue) * 86_400)
    }
}

enum TrashRetention: Int {
    case never = 0, oneDay = 1, sevenDays = 7, oneMonth = 30

    func deadline(for deletion: Date) -> Date? {
        switch self {
        case .never: nil
        case .oneMonth: Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: deletion)
        case .oneDay, .sevenDays: deletion.addingTimeInterval(Double(rawValue) * 86_400)
        }
    }
}

struct CleanupPolicy: Equatable {
    var clear: CleanupInterval
    var delete: TrashRetention

    func deadline(for record: TaskRecord) -> Date? {
        if let deletion = record.deletedAt { return delete.deadline(for: deletion) }
        guard let completion = record.completedAt, completion != record.restoredCompletion else { return nil }
        return clear.deadline(for: completion)
    }
}

@Model
final class CompletionArchive {
    var count: Int
    init(count: Int) { self.count = count }
}

@MainActor
enum CompletedTaskCleanup {
    static func apply(_ records: [TaskRecord], policy: CleanupPolicy, now: Date, context: ModelContext) throws {
        let expired = records.filter { policy.deadline(for: $0).map { $0 <= now } ?? false }
        guard !expired.isEmpty else { return }
        do {
            let count = expired.filter { $0.deletedAt != nil && $0.countedCompletion }.count
            if count > 0 {
                if let archive = try context.fetch(FetchDescriptor<CompletionArchive>()).first {
                    archive.count += count
                } else {
                    context.insert(CompletionArchive(count: count))
                }
            }
            for record in expired {
                // Older stores may contain completed repeats without a successor.
                if record.deletedAt == nil {
                    scheduleNext(after: record, context: context)
                    record.deletedAt = now
                } else {
                    context.delete(record)
                }
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func withdrawNext(after record: TaskRecord, context: ModelContext) throws {
        var nextKey = record.successorKey
        while let key = nextKey {
            let query = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.occurrenceKey == key })
            guard let next = try context.fetch(query).first else { break }
            if next.completedAt == nil {
                if next.deletedAt == nil {
                    if next.countedCompletion {
                        if let archive = try context.fetch(FetchDescriptor<CompletionArchive>()).first {
                            archive.count += 1
                        } else {
                            context.insert(CompletionArchive(count: 1))
                        }
                    }
                    context.delete(next)
                }
                break
            }
            nextKey = next.successorKey
        }
        record.successorKey = nil
    }

    static func scheduleNext(after record: TaskRecord, context: ModelContext) {
        guard record.successorKey == nil, let completion = record.completedAt,
              let rule = RepeatRule(rawValue: record.repeatRule), rule != .never else { return }
        let calendar = Calendar(identifier: .gregorian)
        let scheduled = record.dueDay.flatMap { try? TaskRecord.dayFormat.parseStrategy.parse($0) }
        let anchor = calendar.startOfDay(for: max(scheduled ?? completion, completion))
        let weekday = record.repeatDay ?? calendar.component(.weekday, from: scheduled ?? completion)
        let monthDay = record.repeatDay ?? calendar.component(.day, from: scheduled ?? completion)
        let selectedDays = Set(record.repeatWeekdays.filter { (1...7).contains($0) })
        guard rule != .custom || !selectedDays.isEmpty else { return }
        var date = anchor
        repeat {
            guard let day = calendar.date(byAdding: .day, value: 1, to: date) else { return }
            date = day
            switch rule {
            case .daily: break
            case .weekdays:
                if [1, 7].contains(calendar.component(.weekday, from: date)) { continue }
            case .weekends:
                if ![1, 7].contains(calendar.component(.weekday, from: date)) { continue }
            case .custom:
                if !selectedDays.contains(calendar.component(.weekday, from: date)) { continue }
            case .weekly:
                if calendar.component(.weekday, from: date) != min(7, max(1, weekday)) { continue }
            case .monthly:
                let length = calendar.range(of: .day, in: .month, for: date)!.count
                if calendar.component(.day, from: date) != min(length, max(1, monthDay)) { continue }
            case .never: return
            }
            break
        } while true
        let next = TaskRecord(title: record.title)
        let key = UUID()
        next.occurrenceKey = key
        record.successorKey = key
        next.dueDay = date.formatted(TaskRecord.dayFormat)
        next.repeatRule = record.repeatRule
        next.repeatWeekdays = record.repeatWeekdays
        next.repeatDay = record.repeatDay
        next.link = record.link
        next.group = record.group
        next.isUrgent = record.isUrgent
        next.subtasks = record.subtasks.map { Subtask(title: $0.title) }
        context.insert(next)
    }
}
