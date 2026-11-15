import Foundation
import SwiftData
import Testing
@testable import DODO

@MainActor
@Test func dailyRolloverCompletesPreviousOccurrenceAndCreatesTodayOnce() throws {
    let container = try ModelContainer(for: TaskRecord.self, CompletionArchive.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let now = try TaskRecord.dayFormat.parseStrategy.parse("2026-11-16").addingTimeInterval(3600)
    let task = TaskRecord(title: "Daily routine")
    task.dueDay = "2026-11-15"
    task.repeatRule = RepeatRule.daily.rawValue
    task.isUrgent = true
    task.link = URL(string: "https://example.com")
    task.subtasks = [Subtask(title: "First", isComplete: true), Subtask(title: "Second")]
    let list = TaskGroup(name: "Home")
    list.sections = [TaskListSection(name: "Morning")]
    task.group = list
    task.sectionID = list.sections[0].id
    context.insert(task)
    try context.save()
    try CompletedTaskCleanup.rollOver([task], now: now, context: context)
    let records = try context.fetch(FetchDescriptor<TaskRecord>())
    let next = try #require(records.first { $0.completedAt == nil })
    #expect(records.count == 2 && task.completedAt == now && task.countedCompletion)
    #expect(task.dueDay == "2026-11-15" && task.subtasks.allSatisfy(\.isComplete))
    #expect(next.dueDay == "2026-11-16" && next.title == task.title)
    #expect(next.isUrgent && next.link == task.link && next.group === list && next.sectionID == task.sectionID)
    #expect(next.subtasks.count == 2 && next.subtasks.allSatisfy { !$0.isComplete })
    #expect(next.occurrenceKey == task.successorKey)
    try CompletedTaskCleanup.rollOver(records, now: now, context: context)
    #expect(try context.fetchCount(FetchDescriptor<TaskRecord>()) == 2)
    // Restoring a completed occurrence must withdraw its successor and remain actionable.
    try task.setCompleted(false, in: context)
    try context.save()
    try CompletedTaskCleanup.rollOver(try context.fetch(FetchDescriptor<TaskRecord>()), now: now, context: context)
    #expect(task.completedAt == nil)
    #expect(try context.fetchCount(FetchDescriptor<TaskRecord>()) == 1)
}

@MainActor
@Test func rolloverSkipsMissedDaysAndHonorsRepeatRules() throws {
    let cases: [(RepeatRule, String, String, String, Int?, [Int])] = [
        (.daily, "2026-11-01", "2026-11-16", "2026-11-16", nil, []),
        (.weekly, "2026-11-03", "2026-11-16", "2026-11-17", nil, []),
        (.weekdays, "2026-11-13", "2026-11-16", "2026-11-16", nil, []),
        (.weekends, "2026-11-14", "2026-11-16", "2026-11-21", nil, []),
        (.monthly, "2026-01-31", "2026-02-28", "2026-02-28", 31, []),
        (.custom, "2026-11-03", "2026-11-16", "2026-11-17", nil, [3, 5])
    ]
    for (rule, due, today, expected, monthDay, weekdays) in cases {
        let container = try ModelContainer(for: TaskRecord.self,
                                          configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let task = TaskRecord(title: rule.rawValue)
        task.dueDay = due; task.repeatRule = rule.rawValue
        task.repeatDay = monthDay; task.repeatWeekdays = weekdays
        container.mainContext.insert(task)
        let now = try TaskRecord.dayFormat.parseStrategy.parse(today)
        try CompletedTaskCleanup.rollOver([task], now: now, context: container.mainContext)
        let records = try container.mainContext.fetch(FetchDescriptor<TaskRecord>())
        #expect(records.count == 2)
        #expect(records.first { $0.completedAt == nil }?.dueDay == expected)
    }
}

@MainActor
@Test func rolloverLeavesNonRepeatingUndatedDeletedAndCurrentTasksUntouched() throws {
    let container = try ModelContainer(for: TaskRecord.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let now = try TaskRecord.dayFormat.parseStrategy.parse("2026-11-16")
    let ordinary = TaskRecord(title: "Ordinary")
    ordinary.dueDay = "2026-11-15"
    let undated = TaskRecord(title: "Undated")
    undated.repeatRule = RepeatRule.daily.rawValue
    let deleted = TaskRecord(title: "Deleted")
    deleted.repeatRule = RepeatRule.daily.rawValue; deleted.dueDay = "2026-11-15"; deleted.deletedAt = now
    let current = TaskRecord(title: "Today")
    current.repeatRule = RepeatRule.daily.rawValue; current.dueDay = "2026-11-16"
    let records = [ordinary, undated, deleted, current]
    for task in records { container.mainContext.insert(task) }
    try CompletedTaskCleanup.rollOver(records, now: now, context: container.mainContext)
    #expect(records.allSatisfy { $0.completedAt == nil && $0.successorKey == nil })
    #expect(try container.mainContext.fetchCount(FetchDescriptor<TaskRecord>()) == 4)
}


@MainActor
@Test func rolloverWaitsForTheNextScheduledOccurrence() throws {
    let cases: [(RepeatRule, String, String, Int?, [Int])] = [
        (.weekly, "2026-11-09", "2026-11-16", nil, []),
        (.monthly, "2026-11-05", "2026-12-05", 5, []),
        (.monthly, "2026-01-31", "2026-02-28", nil, []),
        (.monthly, "2028-01-31", "2028-02-29", 31, []),
        (.weekdays, "2026-11-13", "2026-11-16", nil, []),
        (.weekends, "2026-11-15", "2026-11-21", nil, []),
        (.custom, "2026-11-10", "2026-11-12", nil, [3, 5])
    ]
    for (rule, due, nextDay, monthDay, weekdays) in cases {
        let container = try ModelContainer(for: TaskRecord.self,
                                          configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let task = TaskRecord(title: rule.rawValue)
        task.dueDay = due; task.repeatRule = rule.rawValue
        task.repeatDay = monthDay; task.repeatWeekdays = weekdays
        context.insert(task)
        let boundary = try TaskRecord.dayFormat.parseStrategy.parse(nextDay)
        #expect(CompletedTaskCleanup.rolloverDeadline(for: task) == boundary)
        try CompletedTaskCleanup.rollOver([task], now: boundary.addingTimeInterval(-1), context: context)
        #expect(task.completedAt == nil && task.successorKey == nil)
        #expect(try context.fetchCount(FetchDescriptor<TaskRecord>()) == 1)
        try CompletedTaskCleanup.rollOver([task], now: boundary, context: context)
        let records = try context.fetch(FetchDescriptor<TaskRecord>())
        let next = try #require(records.first { $0.completedAt == nil })
        #expect(task.completedAt == boundary && next.dueDay == nextDay)
        #expect(records.count == 2)
        if rule == .monthly && due.hasSuffix("-31") {
            #expect(next.repeatDay == 31)
            #expect(CompletedTaskCleanup.rolloverDeadline(for: next)?.formatted(TaskRecord.dayFormat)
                    == String(nextDay.prefix(4)) + "-03-31")
        }
    }
}
