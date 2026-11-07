import Foundation
import SwiftData

enum CleanupInterval: Int, CaseIterable {
    case never = 0, oneDay = 1, sevenDays = 7

    func deadline(for completion: Date) -> Date? {
        self == .never ? nil : completion.addingTimeInterval(Double(rawValue) * 86_400)
    }
}

@Model
final class CompletionArchive {
    var count: Int
    init(count: Int) { self.count = count }
}

@MainActor
enum CompletedTaskCleanup {
    static func purge(_ records: [TaskRecord], interval: CleanupInterval, now: Date, context: ModelContext) throws {
        guard interval != .never else { return }
        let expired = records.filter {
            guard let completed = $0.completedAt, let deadline = interval.deadline(for: completed) else { return false }
            return deadline <= now
        }
        guard !expired.isEmpty else { return }
        do {
            let count = expired.filter(\.countedCompletion).count
            if count > 0 {
                if let archive = try context.fetch(FetchDescriptor<CompletionArchive>()).first {
                    archive.count += count
                } else {
                    context.insert(CompletionArchive(count: count))
                }
            }
            for record in expired {
                // Older stores may contain completed repeats without a successor.
                if record.deletedAt == nil { scheduleNext(after: record, context: context) }
                context.delete(record)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func scheduleNext(after record: TaskRecord, context: ModelContext) {
        guard record.successorKey == nil, let completion = record.completedAt,
              let rule = RepeatRule(rawValue: record.repeatRule), rule != .never else { return }
        let calendar = Calendar(identifier: .gregorian)
        let scheduled = record.dueDay.flatMap { try? TaskRecord.dayFormat.parseStrategy.parse($0) }
        let anchor = calendar.startOfDay(for: max(scheduled ?? completion, completion))
        let weekday = record.repeatDay ?? calendar.component(.weekday, from: scheduled ?? completion)
        let monthDay = record.repeatDay ?? calendar.component(.day, from: scheduled ?? completion)
        var date = anchor
        repeat {
            guard let day = calendar.date(byAdding: .day, value: 1, to: date) else { return }
            date = day
            switch rule {
            case .daily: break
            case .weekdays:
                if [1, 7].contains(calendar.component(.weekday, from: date)) { continue }
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
        next.repeatDay = record.repeatDay
        next.group = record.group
        next.isUrgent = record.isUrgent
        next.subtasks = record.subtasks.map { Subtask(title: $0.title) }
        context.insert(next)
    }
}
