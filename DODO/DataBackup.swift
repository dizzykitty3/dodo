import Foundation
import SwiftData

enum BackupError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}

struct BackupPreferences: Codable {
    var todayPreviewLimit: Int
    var urgentPreviewLimit: Int
    var hideUndatedFromTodayPreview: Bool
    var sortScheduledByDate: Bool
    var sortCompletedByDate: Bool
    var completedCleanupInterval: Int
    var trashRetention: Int
    var listBadgeContent: String
    var listBadgeSeparator: String
    var dateBadgeAbbreviatesMonth: Bool
    var dateBadgeOrder: String
    var dateBadgeSeparator: String
    var dateBadgeShowsCurrentYear: Bool
    var dateBadgeInitialized: Bool
    var dateBadgeInitialPattern: String?
    var dateBadgeInitialOrder: String?
    var dateBadgeInitialSeparator: String?

    init(defaults: UserDefaults) {
        func value<T>(_ key: String, _ fallback: T) -> T { defaults.object(forKey: key) as? T ?? fallback }
        todayPreviewLimit = value("todayPreviewLimit", 5)
        urgentPreviewLimit = value("urgentPreviewLimit", 5)
        hideUndatedFromTodayPreview = value("hideUndatedFromTodayPreview", false)
        sortScheduledByDate = value("sortScheduledByDate", true)
        sortCompletedByDate = value("sortCompletedByDate", true)
        completedCleanupInterval = value("completedCleanupInterval", 0)
        trashRetention = value("trashRetention", 7)
        listBadgeContent = value("listBadgeContent", ListBadgeContent.list.rawValue)
        listBadgeSeparator = value("listBadgeSeparator", ListBadgeSeparator.space.rawValue)
        dateBadgeAbbreviatesMonth = value("dateBadgeAbbreviatesMonth", false)
        dateBadgeOrder = value("dateBadgeOrder", DateBadgeOrder.yearFirst.rawValue)
        dateBadgeSeparator = value("dateBadgeSeparator", DateBadgeSeparator.dash.rawValue)
        dateBadgeShowsCurrentYear = value("dateBadgeShowsCurrentYear", true)
        dateBadgeInitialized = value("dateBadgeInitialized", false)
        dateBadgeInitialPattern = defaults.string(forKey: "dateBadgeInitialPattern")
        dateBadgeInitialOrder = defaults.string(forKey: "dateBadgeInitialOrder")
        dateBadgeInitialSeparator = defaults.string(forKey: "dateBadgeInitialSeparator")
    }

    func validate() throws {
        guard (-1...5).contains(todayPreviewLimit), (-1...5).contains(urgentPreviewLimit),
              CleanupInterval(rawValue: completedCleanupInterval) != nil,
              TrashRetention(rawValue: trashRetention) != nil,
              ListBadgeContent(rawValue: listBadgeContent) != nil,
              ListBadgeSeparator(rawValue: listBadgeSeparator) != nil,
              DateBadgeOrder(rawValue: dateBadgeOrder) != nil,
              DateBadgeSeparator(rawValue: dateBadgeSeparator) != nil,
              dateBadgeInitialOrder.map({ DateBadgeOrder(rawValue: $0) != nil }) ?? true,
              dateBadgeInitialSeparator.map({ DateBadgeSeparator(rawValue: $0) != nil }) ?? true else {
            throw BackupError.invalid("The file contains invalid settings.")
        }
    }

    func apply(to defaults: UserDefaults) {
        // Only app-owned settings are imported, never arbitrary UserDefaults keys.
        let values: [String: Any?] = [
            "todayPreviewLimit": todayPreviewLimit, "urgentPreviewLimit": urgentPreviewLimit,
            "hideUndatedFromTodayPreview": hideUndatedFromTodayPreview,
            "sortScheduledByDate": sortScheduledByDate, "sortCompletedByDate": sortCompletedByDate,
            "completedCleanupInterval": completedCleanupInterval, "trashRetention": trashRetention,
            "listBadgeContent": listBadgeContent, "listBadgeSeparator": listBadgeSeparator,
            "dateBadgeAbbreviatesMonth": dateBadgeAbbreviatesMonth, "dateBadgeOrder": dateBadgeOrder,
            "dateBadgeSeparator": dateBadgeSeparator, "dateBadgeShowsCurrentYear": dateBadgeShowsCurrentYear,
            "dateBadgeInitialized": dateBadgeInitialized, "dateBadgeInitialPattern": dateBadgeInitialPattern,
            "dateBadgeInitialOrder": dateBadgeInitialOrder, "dateBadgeInitialSeparator": dateBadgeInitialSeparator
        ]
        for (key, value) in values {
            if let value { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
    }
}

struct BackupList: Codable {
    var id: UUID
    var name: String
    var createdAt: Date
    var colorName: String
    var symbolName: String
    var position: Int
    var groups: [TaskListSection]
}

struct BackupTask: Codable {
    var title: String
    var link: URL?
    var createdAt: Date
    var dueDay: String?
    var repeatRule: String
    var repeatDay: Int?
    var repeatWeekdays: [Int]
    var isUrgent: Bool
    var isPersonal: Bool
    var completedAt: Date?
    var occurrenceKey: UUID?
    var successorKey: UUID?
    var deletedAt: Date?
    var restoredCompletion: Date?
    var countedCompletion: Bool
    var listID: UUID?
    var groupID: UUID?
    var subtasks: [Subtask]

    init(_ task: TaskRecord, listID: UUID?) {
        title = task.title; link = task.link; createdAt = task.createdAt; dueDay = task.dueDay
        repeatRule = task.repeatRule; repeatDay = task.repeatDay; repeatWeekdays = task.repeatWeekdays
        isUrgent = task.isUrgent; isPersonal = task.isPersonal; completedAt = task.completedAt
        occurrenceKey = task.occurrenceKey; successorKey = task.successorKey; deletedAt = task.deletedAt
        restoredCompletion = task.restoredCompletion; countedCompletion = task.countedCompletion
        self.listID = listID; groupID = task.sectionID; subtasks = task.subtasks
    }
}

struct DODOBackup: Codable {
    var format = "dodo"
    var schemaVersion = "v1"
    var exportedAt = Date.now
    var preferences: BackupPreferences
    var archivedCompletedCount: Int
    var lists: [BackupList]
    var tasks: [BackupTask]

    static func decode(_ data: Data) throws -> Self {
        struct Header: Decodable { var format: String; var schemaVersion: String }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let header: Header
        do { header = try decoder.decode(Header.self, from: data) }
        catch { throw BackupError.invalid("Choose a DODO JSON data file.") }
        guard header.format == "dodo" else { throw BackupError.invalid("This is not a DODO data file.") }
        guard header.schemaVersion == "v1" else {
            throw BackupError.invalid("This data version is not supported. Update DODO before importing it.")
        }
        let backup: Self
        do { backup = try decoder.decode(Self.self, from: data) }
        catch { throw BackupError.invalid("The DODO data file is incomplete or damaged.") }
        try backup.validate()
        return backup
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(self)
    }

    func validate() throws {
        guard format == "dodo", schemaVersion == "v1" else { throw BackupError.invalid("Unsupported DODO data file.") }
        try preferences.validate()
        func invalid() -> BackupError { .invalid("The file contains invalid tasks, lists, or groups.") }
        guard archivedCompletedCount >= 0,
              !archivedCompletedCount.addingReportingOverflow(tasks.filter(\.countedCompletion).count).overflow,
              Set(lists.map(\.id)).count == lists.count else { throw invalid() }
        let byID = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0) })
        for list in lists {
            guard !list.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  ListCardColor(rawValue: list.colorName) != nil, ListCardIcon(rawValue: list.symbolName) != nil,
                  Set(list.groups.map(\.id)).count == list.groups.count,
                  list.groups.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw invalid() }
        }
        var successors: [UUID: UUID] = [:]
        var occurrenceKeys = Set<UUID>()
        for task in tasks {
            guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let rule = RepeatRule(rawValue: task.repeatRule),
                  task.repeatWeekdays.allSatisfy({ (1...7).contains($0) }),
                  rule != .custom || !task.repeatWeekdays.isEmpty,
                  task.repeatDay.map({ (1...31).contains($0) }) ?? true,
                  Set(task.subtasks.map(\.id)).count == task.subtasks.count else { throw invalid() }
            if let url = task.link {
                guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw invalid() }
            }
            if let day = task.dueDay {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.isLenient = false
                guard let date = formatter.date(from: day), formatter.string(from: date) == day else { throw invalid() }
            }
            if let listID = task.listID {
                guard let list = byID[listID] else { throw invalid() }
                if let groupID = task.groupID, !list.groups.contains(where: { $0.id == groupID }) { throw invalid() }
            } else if task.groupID != nil { throw invalid() }
            if let key = task.occurrenceKey {
                guard occurrenceKeys.insert(key).inserted else { throw invalid() }
                successors[key] = task.successorKey
            }
        }
        // Missing successors are valid after cleanup; cycles would make restoration loop forever.
        var visited = Set<UUID>()
        for key in occurrenceKeys {
            var chain = Set<UUID>()
            var current: UUID? = key
            while let node = current, !visited.contains(node) {
                guard chain.insert(node).inserted else { throw invalid() }
                current = successors[node]
            }
            visited.formUnion(chain)
        }
    }
}

@MainActor
enum BackupStore {
    enum ImportMode { case replace, merge }

    static func snapshot(context: ModelContext, defaults: UserDefaults = .standard) throws -> DODOBackup {
        let lists = try context.fetch(FetchDescriptor<TaskGroup>(sortBy: TaskGroup.displayOrder))
        let ids = Dictionary(uniqueKeysWithValues: lists.map { ($0.persistentModelID, UUID()) })
        let exportedLists = lists.map {
            BackupList(id: ids[$0.persistentModelID]!, name: $0.name, createdAt: $0.createdAt,
                       colorName: $0.colorName, symbolName: $0.symbolName, position: $0.position, groups: $0.sections)
        }
        let tasks = try context.fetch(FetchDescriptor<TaskRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        let archives = try context.fetch(FetchDescriptor<CompletionArchive>())
        return DODOBackup(preferences: BackupPreferences(defaults: defaults),
                          archivedCompletedCount: try sum(archives.map(\.count)),
                          lists: exportedLists, tasks: tasks.map { BackupTask($0, listID: $0.group.flatMap { ids[$0.persistentModelID] }) })
    }

    static func apply(_ backup: DODOBackup, mode: ImportMode, context: ModelContext,
                      defaults: UserDefaults = .standard) throws {
        try backup.validate()
        // Save preexisting edits before starting a single, rollback-safe database update.
        try context.save()
        let autosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        do {
            var lists = try context.fetch(FetchDescriptor<TaskGroup>(sortBy: TaskGroup.displayOrder))
            let existingTasks = try context.fetch(FetchDescriptor<TaskRecord>())
            let archives = try context.fetch(FetchDescriptor<CompletionArchive>())
            if mode == .replace {
                for task in existingTasks { context.delete(task) }
                for list in lists { context.delete(list) }
                for archive in archives { context.delete(archive) }
                lists = []
            } else {
                _ = try sum(archives.map(\.count) + [existingTasks.filter(\.countedCompletion).count,
                                                  backup.archivedCompletedCount, backup.tasks.filter(\.countedCompletion).count])
                for (index, list) in lists.enumerated() { list.position = index }
            }
            var listMap: [UUID: TaskGroup] = [:]
            var groupMap: [UUID: [UUID: UUID]] = [:]
            let orderedLists = backup.lists.sorted { $0.position == $1.position ? $0.createdAt < $1.createdAt : $0.position < $1.position }
            for incoming in orderedLists {
                let existing = mode == .merge ? lists.first { matches($0.name, incoming.name) } : nil
                let list: TaskGroup
                if let existing { list = existing }
                else {
                    list = TaskGroup(name: incoming.name, position: mode == .replace ? incoming.position : lists.count)
                    list.createdAt = incoming.createdAt
                    list.colorName = incoming.colorName
                    list.symbolName = incoming.symbolName
                    context.insert(list)
                    lists.append(list)
                }
                listMap[incoming.id] = list
                var mapping: [UUID: UUID] = [:]
                for group in incoming.groups {
                    if mode == .merge, let existing = list.sections.first(where: { matches($0.name, group.name) }) {
                        mapping[group.id] = existing.id
                    } else {
                        let id = mode == .merge ? UUID() : group.id
                        list.sections.append(TaskListSection(id: id, name: group.name))
                        mapping[group.id] = id
                    }
                }
                groupMap[incoming.id] = mapping
            }
            // Remap the entire repeat graph, including dangling keys, when appending a backup.
            let keys = Set(backup.tasks.flatMap { [$0.occurrenceKey, $0.successorKey].compactMap { $0 } })
            let keyMap = Dictionary(uniqueKeysWithValues: keys.map { ($0, mode == .merge ? UUID() : $0) })
            for incoming in backup.tasks {
                let task = TaskRecord(title: incoming.title)
                task.link = incoming.link; task.createdAt = incoming.createdAt; task.dueDay = incoming.dueDay
                task.repeatRule = incoming.repeatRule; task.repeatDay = incoming.repeatDay
                task.repeatWeekdays = incoming.repeatWeekdays; task.isUrgent = incoming.isUrgent
                task.isPersonal = incoming.isPersonal; task.completedAt = incoming.completedAt
                task.deletedAt = incoming.deletedAt; task.restoredCompletion = incoming.restoredCompletion
                task.countedCompletion = incoming.countedCompletion
                task.occurrenceKey = incoming.occurrenceKey.flatMap { keyMap[$0] }
                task.successorKey = incoming.successorKey.flatMap { keyMap[$0] }
                task.group = incoming.listID.flatMap { listMap[$0] }
                if let listID = incoming.listID, let groupID = incoming.groupID {
                    task.sectionID = groupMap[listID]?[groupID]
                }
                task.subtasks = incoming.subtasks.map {
                    Subtask(id: mode == .merge ? UUID() : $0.id, title: $0.title, isComplete: $0.isComplete)
                }
                context.insert(task)
            }
            if backup.archivedCompletedCount > 0 { context.insert(CompletionArchive(count: backup.archivedCompletedCount)) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        // Never replace preferences until the database has been saved successfully.
        if mode == .replace { backup.preferences.apply(to: defaults) }
    }

    private static func matches(_ left: String, _ right: String) -> Bool {
        left.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(right.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private static func sum(_ values: [Int]) throws -> Int {
        try values.reduce(0) { total, value in
            let result = total.addingReportingOverflow(value)
            guard value >= 0, !result.overflow else { throw BackupError.invalid("The completion statistics are invalid.") }
            return result.partialValue
        }
    }
}
