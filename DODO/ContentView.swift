import SwiftUI
import SwiftData

enum TaskList: Hashable, Identifiable {
    case today, urgent, completed, scheduled, all, inProgress, deleted, custom(TaskListRecord)

    static let builtIns: [TaskList] = [.urgent, .today, .scheduled, .all, .inProgress, .completed, .deleted]

    var title: String {
        switch self {
        case .today: "Today"
        case .urgent: "Urgent"
        case .completed: "Completed"
        case .scheduled: "Scheduled"
        case .all: "All Tasks"
        case .inProgress: "In Progress"
        case .deleted: "Recently Deleted"
        case .custom(let list): list.name
        }
    }
    var list: TaskListRecord? {
        if case .custom(let list) = self { return list }
        return nil
    }
    var hasPreview: Bool { self == .today || self == .urgent }
    var isCompact: Bool { self == .all || self == .inProgress || self == .completed || self == .deleted }

    var id: Self { self }
    var color: Color {
        switch self {
        case .deleted: Color.gray
        case .custom(let list): list.cardColor.color
        case .inProgress: Color(red: 0.30, green: 0.49, blue: 0.48)
        case .all: Color(red: 0.37, green: 0.39, blue: 0.44)
        case .today: Color(red: 0.35, green: 0.56, blue: 0.72)
        case .urgent: Color(red: 0.73, green: 0.39, blue: 0.54)
        case .completed: Color(red: 0.46, green: 0.50, blue: 0.53)
        case .scheduled: Color(red: 0.74, green: 0.44, blue: 0.44)
        }
    }
    var canCreateTask: Bool { self != .completed && self != .deleted }

    var symbol: String {
        switch self {
        case .deleted: "trash"
        case .custom(let list): list.cardIcon.rawValue
        case .all: "tray.full.fill"
        case .inProgress: "circle.lefthalf.filled"
        case .today: "sun.max.fill"
        case .urgent: "star.fill"
        case .completed: "checkmark"
        case .scheduled: "calendar"
        }
    }
}

private enum Panel: Identifiable, Hashable {
    case search(TaskList), compose(TaskList?, tagID: UUID? = nil), newList, editList(TaskListRecord)

    var isSearch: Bool {
        if case .search = self { return true }
        return false
    }
    var id: Self { self }
}

struct ContentView: View {
    private var listBadge = ListBadgePreferences()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hideYearProgress") private var hideYearProgress = false
    @AppStorage("completedCleanupInterval") private var cleanupInterval = CleanupInterval.never
    @AppStorage("trashRetention") private var trashRetention = TrashRetention.sevenDays
    @Query private var archives: [CompletionArchive]

    private struct CleanupSchedule: Equatable {
        let policy: CleanupPolicy
        let deadline: Date?
        let revision: Int
    }

    @AppStorage("todayHideOlderCompletedSubtasks") private var hideOlderCompletedSubtasks = false
    @AppStorage("todayHideOldOverdue") private var hideOldOverdue = false
    @AppStorage("todayOverdueDays") private var overdueDays = 30
    @AppStorage("todayBeforeOverdue") private var todayBeforeOverdue = false
    @State private var clockRevision = 0

    private var cleanupSchedule: CleanupSchedule {
        let policy = CleanupPolicy(clear: cleanupInterval, delete: trashRetention)
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))
        let deadlines = tasks.compactMap { policy.deadline(for: $0) }
            + tasks.compactMap { CompletedTaskCleanup.rolloverDeadline(for: $0) }
            + [midnight].compactMap { $0 }
        let deadline = scenePhase == .active ? deadlines.min() : nil
        return CleanupSchedule(policy: policy, deadline: deadline, revision: clockRevision)
    }

    @AppStorage("hideUndatedFromTodayPreview") private var hideUndatedFromTodayPreview = false
    @AppStorage("todayPreviewLimit") private var todayPreviewLimit = 5
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var tasks: [TaskRecord]
    @AppStorage("urgentPreviewLimit") private var urgentPreviewLimit = 5
    @Query(sort: TaskListRecord.displayOrder) private var lists: [TaskListRecord]
    @State private var storageError: String?
    @State private var panel: Panel?
    @State private var panelSessionID = UUID()
    @Environment(\.modelContext) private var context
    @AppStorage("sortScheduledByDate") private var sortScheduled = true
    @AppStorage("sortCompletedByDate") private var sortCompleted = true
    @State private var pendingRemoval: [PersistentIdentifier: Date] = [:]
    @State private var didCreateTask = false
    @State private var toastMessage = ""
    @State private var toastID: UUID?
    @State private var query = ""
    @State private var path: [TaskList] = []
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var mainPage = MainPage.tasks
    @State private var settingsPath = NavigationPath()
    @State private var editingTask: TaskRecord?
    @State private var searchEditingTask: TaskRecord?
    @State private var editSessionID = UUID()

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Tasks", systemImage: "checklist", value: MainPage.tasks) {
                NavigationStack(path: $path) {
                    homePage
                        .navigationTitle("DODO")
                        .navigationBarTitleDisplayMode(.large)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) { searchButton(from: .all) }
                        }
                        .navigationDestination(for: TaskList.self) { list in
                            taskRows(in: list)
                                .navigationTitle(list.title)
                                .toolbar(.visible, for: .navigationBar)
                                .toolbar(.visible, for: .tabBar)
                                .toolbar {
                                    if let customList = list.list {
                                        ToolbarItem(placement: .topBarTrailing) {
                                            NewTaskTagButton(list: customList)
                                        }
                                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                                    }
                                    ToolbarItemGroup(placement: .topBarTrailing) {
                                        if list == .completed || list == .deleted {
                                            BulkTaskActions(permanently: list == .deleted) { message in
                                                pendingRemoval = [:]
                                                showToast(message)
                                            }
                                        }
                                        if let customList = list.list {
                                            Button("Edit List", systemImage: "pencil") { present(.editList(customList)) }
                                                .labelStyle(.iconOnly)
                                        }
                                        searchButton(from: list)
                                    }
                                }
                        }
                }
                .environment(\.horizontalSizeClass, horizontalSizeClass)
            }
            Tab("Settings", systemImage: "gearshape", value: MainPage.settings) {
                NavigationStack(path: $settingsPath) {
                    settingsPage
                        .navigationBarTitleDisplayMode(.large)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) { searchButton(from: .all) }
                        }
                }
                .environment(\.horizontalSizeClass, horizontalSizeClass)
            }
            Tab("New Task", systemImage: "square.and.pencil", value: MainPage.compose, role: composeTabRole) {
                Color.clear
            }
        }
        .environment(\.horizontalSizeClass, .compact)
        .alert("Couldn’t save changes", isPresented: Binding(get: { storageError != nil }, set: { if !$0 { storageError = nil } })) {
            Button("OK") { storageError = nil }
        } message: { Text(storageError ?? "") }
        .task(id: cleanupSchedule) {
            let schedule = cleanupSchedule
            guard let deadline = schedule.deadline else { return }
            do {
                if deadline > .now { try await Task.sleep(for: .seconds(deadline.timeIntervalSinceNow)) }
                try Task.checkCancellation()
                try CompletedTaskCleanup.rollOver(tasks, now: .now, context: context)
                try CompletedTaskCleanup.apply(tasks, policy: schedule.policy, now: .now, context: context)
                clockRevision += 1
            } catch is CancellationError {
                return
            } catch {
                storageError = error.localizedDescription
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            clockRevision += 1
        }
        .overlay { toastPill }
        .task(id: toastID) {
            guard toastID != nil else { return }
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            toastID = nil
        }
        .sheet(item: $editingTask) { record in
            taskEditorSheet(record)
        }
        .sheet(item: $panel, onDismiss: finishCompose) { selected in
            NavigationStack {
                Group {
                    switch selected {
                    case .search(let source):
                        searchResults(from: source)
                            .navigationTitle("Search")
                            .navigationBarTitleDisplayMode(.inline)
                            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search tasks")
                            .toolbar { sheetCloseButton }
                    case .newList:
                        CustomListEditor()
                    case .editList(let list):
                        CustomListEditor(list: list) { path = [] }
                    case .compose(let composeSource, let tagID):
                        TaskEditor(presetToday: composeSource == .today, presetUrgent: composeSource == .urgent,
                                   presetList: composeSource?.list, presetTagID: tagID, onCreate: { didCreateTask = true })
                    }
                }
                .sheet(item: $searchEditingTask) { record in
                    taskEditorSheet(record)
                }
            }
            .id(panelSessionID)
            .overlay { if selected.isSearch { toastPill } }
            .confirmSheetDismissal()
            .presentationDetents([.large])
        }
    }

    private enum MainPage: Hashable {
        case tasks, settings, compose
    }

    private var composeTabRole: TabRole {
        if #available(iOS 27.0, *) { return .prominent }
        return .search
    }

    private var tabSelection: Binding<MainPage> {
        Binding(get: { mainPage }, set: { page in
            if page == .compose {
                present(.compose(mainPage == .tasks ? path.last : nil))
            } else {
                mainPage = page
                UISelectionFeedbackGenerator().selectionChanged()
            }
        })
    }

    private var homePage: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !hideYearProgress { YearProgressCard() }
                card(.urgent)
                card(.today)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    card(.scheduled)
                    ForEach(lists) { card(.custom($0)) }
                    newListCard
                }
                card(.all)
                card(.inProgress)
                card(.completed)
                card(.deleted)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var settingsPage: some View {
        SettingsView(previewLimit: $todayPreviewLimit, urgentPreviewLimit: $urgentPreviewLimit,
                     hideUndatedFromTodayPreview: $hideUndatedFromTodayPreview,
                     sortScheduled: $sortScheduled, sortCompleted: $sortCompleted,
                     completedCount: archives.reduce(0) { $0 + $1.count } + tasks.filter(\.countedCompletion).count,
                     onImport: {
                         path = []
                         pendingRemoval = [:]
                     })
    }

    private func taskEditorSheet(_ record: TaskRecord) -> some View {
        NavigationStack {
            TaskEditor(task: record, onDelete: { showToast("Task deleted") })
        }
        .id(editSessionID)
        .confirmSheetDismissal()
        .presentationDetents([.large])
    }

    private func present(_ selection: Panel) {
        // A presentation owns its draft; reopening must not reuse the previous form state.
        panelSessionID = UUID()
        panel = selection
    }

    private var sheetCloseButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark") { panel = nil }
        }
    }

    private func finishCompose() {
        searchEditingTask = nil
        if didCreateTask {
            didCreateTask = false
            showToast("Task saved")
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        toastID = UUID()
        AccessibilityNotification.Announcement(message).post()
    }

    @ViewBuilder
    private var toastPill: some View {
        if toastID != nil {
            Label(toastMessage, systemImage: "checkmark")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .allowsHitTesting(false)
        }
    }

    private func searchButton(from source: TaskList) -> some View {
        Button("Search", systemImage: "magnifyingglass") {
            query = ""
            present(.search(source))
        }
        .labelStyle(.iconOnly)
    }

    private func searchResults(from searchSource: TaskList) -> some View {
        let matches = tasks.filter {
            ($0.deletedAt == nil || searchSource == .deleted) && (query.isEmpty || $0.title.localizedStandardContains(query))
        }
        let localIDs = Set(items(searchSource).map(\.persistentModelID))
        return List {
            if searchSource == .all {
                rows(matches, showsCheckbox: false)
            } else {
                let local = matches.filter { localIDs.contains($0.persistentModelID) }
                let other = matches.filter { !localIDs.contains($0.persistentModelID) }
                if !local.isEmpty { Section(searchSource.title) { rows(local, showsCheckbox: false) } }
                if !other.isEmpty { Section("Other Tasks") { rows(other, showsCheckbox: false) } }
            }
        }
        .overlay { if matches.isEmpty { ContentUnavailableView.search(text: query) } }
    }

    @ViewBuilder
    private func scheduledSections(_ records: [TaskRecord], today: Date) -> some View {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: today)
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: start),
           let week = calendar.dateInterval(of: .weekOfYear, for: start),
           let followingWeek = calendar.dateInterval(of: .weekOfYear, for: week.end) {
            let todayKey = start.formatted(TaskRecord.dayFormat)
            let tomorrowKey = tomorrow.formatted(TaskRecord.dayFormat)
            let nextWeekKey = week.end.formatted(TaskRecord.dayFormat)
            let laterKey = followingWeek.end.formatted(TaskRecord.dayFormat)
            let sorted = records.sorted { ($0.dueDay ?? "") < ($1.dueDay ?? "") }
            let buckets = Dictionary(grouping: sorted) { task in
                let day = task.dueDay ?? ""
                if day < todayKey { return "Overdue" }
                if day == todayKey { return "Today" }
                if day == tomorrowKey { return "Tomorrow" }
                if day < nextWeekKey { return "This Week" }
                if day < laterKey { return "Next Week" }
                return "Later"
            }
            let upcoming = ["Tomorrow", "This Week", "Next Week", "Later"].filter { buckets[$0] != nil }
            daySection("Overdue", buckets["Overdue"] ?? [])
            daySection("Today", buckets["Today"] ?? [])
            if (buckets["Overdue"] != nil || buckets["Today"] != nil) && !upcoming.isEmpty {
                dateSectionDivider
            }
            ForEach(upcoming, id: \.self) { title in
                daySection(title, buckets[title] ?? [])
            }
        }
    }

    private var dateSectionDivider: some View {
        Section {
            Circle()
                .frame(width: 18, height: 18)
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityHidden(true)
        }
        .listSectionMargins(.vertical, 0)
    }

    private func taskRows(in list: TaskList) -> some View {
        let cutoff = Calendar.current.date(byAdding: .day, value: -max(1, min(overdueDays, 3650)), to: .now)!
            .formatted(TaskRecord.dayFormat)
        let records = items(list, includePending: true).filter { record in
            list != .today || !hideOldOverdue || record.dueDay.map { $0 >= cutoff } ?? true
        }
        return List {
            if list == .today {
                let today = Date.now.formatted(TaskRecord.dayFormat)
                let overdue = records.filter { $0.dueDay.map { $0 < today } ?? false }
                let dueToday = records.filter { $0.dueDay == today }
                let undated = records.filter { $0.dueDay == nil }
                if todayBeforeOverdue {
                    daySection("Today", dueToday)
                    daySection("Overdue", overdue)
                } else {
                    daySection("Overdue", overdue)
                    daySection("Today", dueToday)
                }
                if (!overdue.isEmpty || !dueToday.isEmpty) && !undated.isEmpty {
                    dateSectionDivider
                }
                daySection("No Date", undated)
            } else if let customList = list.list {
                let tasksByTag = Dictionary(grouping: records, by: \.tagID)
                Section {
                    rows(tasksByTag[nil] ?? [], showsCheckbox: true)
                    Button("New Task") { present(.compose(list, tagID: nil)) }
                        .tint(.blue)
                } header: {
                    Text("Untagged")
                }
                ForEach(customList.tags) { tag in
                    Section(tag.name) {
                        rows(tasksByTag[tag.id] ?? [], showsCheckbox: true)
                        Button("New Task") { present(.compose(list, tagID: tag.id)) }
                            .tint(.blue)
                    }
                }
            } else if list == .scheduled && sortScheduled {
                scheduledSections(records, today: .now)
            } else if list == .completed && sortCompleted {
                rows(records.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }, showsCheckbox: true)
            } else {
                rows(records, showsCheckbox: true)
            }
        }
        .environment(\.hidesOlderCompletedSubtasks, list == .today && hideOlderCompletedSubtasks)
        .environment(\.showsTaskListBadge, list.list == nil)
        .overlay {
            if records.isEmpty && list.list == nil {
                if list.canCreateTask {
                    ContentUnavailableView("No Tasks", systemImage: list.symbol,
                                           description: Text("Tap the compose button in the bottom-right corner to create a task."))
                } else if list == .completed {
                    ContentUnavailableView("No Completed Tasks", systemImage: list.symbol,
                                           description: Text("Tasks you complete appear here."))
                } else {
                    ContentUnavailableView("No Recently Deleted Tasks", systemImage: list.symbol,
                                           description: Text("Tasks you delete appear here before permanent deletion."))
                }
            }
        }
    }

    @ViewBuilder
    private func daySection(_ title: String, _ records: [TaskRecord]) -> some View {
        if !records.isEmpty { Section(title) { rows(records, showsCheckbox: true) } }
    }

    private func rows(_ records: [TaskRecord], showsCheckbox: Bool) -> some View {
        ForEach(records) { record in
            if record.deletedAt != nil {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TaskTitle(title: record.title)
                            TaskBadges(record: record)
                        }
                        TaskListDetails(record: record, badgeTitle: listBadge.title(for: record))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Restore") {
                        record.restoredCompletion = record.completedAt
                        record.deletedAt = nil
                        do { try context.save(); showToast("Task restored") }
                        catch { context.rollback(); storageError = error.localizedDescription }
                    }
                    .buttonStyle(.glass)
                }
            } else {
                CompletionRow(record: record, onEdit: {
                    editSessionID = UUID()
                    if panel?.isSearch == true { searchEditingTask = record }
                    else { editingTask = record }
                },
                              toggle: showsCheckbox ? { child in try toggleCompletion(record, child: child) } : nil)
            }
        }
    }

    private func toggleCompletion(_ record: TaskRecord, child: UUID?) throws {
        let id = record.persistentModelID
        let previous = record.completedAt
        do {
            if let child {
                var edited = record.displayedSubtasks
                guard let index = edited.firstIndex(where: { $0.id == child }) else { return }
                edited[index].isComplete.toggle()
                record.subtasks = edited
                try record.syncSubtaskCompletion(in: context)
            } else {
                guard record.subtasks.isEmpty else { return }
                try record.setCompleted(previous == nil, in: context)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        UISelectionFeedbackGenerator().selectionChanged()
        let completion = record.completedAt
        guard previous != completion else { return }
        pendingRemoval[id] = completion
        guard let completion else { return }
        Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard pendingRemoval[id] == completion else { return }
            pendingRemoval[id] = nil
        }
    }

    private func items(_ list: TaskList, includePending: Bool = false) -> [TaskRecord] {
        let today = Date.now.formatted(TaskRecord.dayFormat)
        return tasks.filter { task in
            if list == .deleted { return task.deletedAt != nil }
            guard task.deletedAt == nil else { return false }
            if list == .all { return true }
            if list == .completed { return task.completedAt != nil }
            guard task.completedAt == nil || (includePending && pendingRemoval[task.persistentModelID] == task.completedAt) else { return false }
            switch list {
            case .all, .inProgress: return true
            case .today: return task.dueDay.map { $0 <= today } ?? true
            case .urgent: return task.isUrgent
            case .scheduled: return task.dueDay != nil
            case .custom(let list): return task.list == list
            case .completed, .deleted: return false
            }
        }
    }

    private var newListCard: some View {
        Button { present(.newList) } label: {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "plus")
                    .font(.title.bold())
                    .accessibilityHidden(true)
                Text("New List").font(.headline)
            }
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    private func card(_ list: TaskList) -> some View {
        let entries = items(list)
        let limit = list == .urgent ? urgentPreviewLimit : todayPreviewLimit
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let visible = !list.isCompact || !entries.isEmpty
        return Group {
            if visible {
                NavigationLink(value: list) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center) {
                            ListSymbol(name: list.symbol).font(.title3.weight(.semibold))
                            if list.hasPreview { Text(list.title).font(.title2.bold()) }
                            if list.isCompact { Text(list.title).font(.headline) }
                            Spacer(minLength: 2)
                            Text("\(entries.count)").font(.title.bold()).monospacedDigit()
                        }
                        if list.hasPreview {
                            let preview = list == .today && hideUndatedFromTodayPreview ? entries.filter { $0.dueDay != nil } : entries
                            ForEach(preview.prefix(limit == -1 ? entries.count : max(0, limit))) { task in
                                Divider().overlay(.white.opacity(0.25))
                                HStack(spacing: 10) {
                                    Image(systemName: "circle").foregroundStyle(.white.opacity(0.7))
                                    TaskTitle(title: task.title).font(.body)
                                }
                            }
                        } else if !list.isCompact {
                            Text(list.title).font(.headline)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, list.hasPreview ? 20 : 16)
                    .padding(.vertical, list.isCompact ? 8 : list.hasPreview ? 20 : 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(list.color.gradient, in: shape)
                    .contentShape(shape)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: visible)
    }
}

private let taskCheckboxWidth: CGFloat = 44

private extension EnvironmentValues {
    @Entry var showsTaskListBadge = true
    @Entry var hidesOlderCompletedSubtasks = false
}

private struct CompletionRow: View {
    @Environment(\.showsTaskListBadge) private var showsTaskListBadge
    @Environment(\.hidesOlderCompletedSubtasks) private var hidesOlderCompletedSubtasks
    private var listBadge = ListBadgePreferences()
    let record: TaskRecord
    let onEdit: () -> Void
    let toggle: ((UUID?) throws -> Void)?
    @State private var errorMessage: String?

    private var visibleSubtasks: [Subtask] {
        let children = record.displayedSubtasks
        guard hidesOlderCompletedSubtasks else { return children }
        // Legacy subtasks have no completion timestamp; use their list order as a stable fallback.
        let latest = children.filter(\.isComplete).enumerated().max {
            let lhs = $0.element.completedAt ?? .distantPast
            let rhs = $1.element.completedAt ?? .distantPast
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }?.element.id
        return children.filter { !$0.isComplete || $0.id == latest }
    }

    var body: some View {
        let completed = record.completedAt != nil
        let badgeTitle = showsTaskListBadge ? listBadge.title(for: record) : nil
        let overdue = !completed && (record.dueDay.map { $0 < Date.now.formatted(TaskRecord.dayFormat) } ?? false)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: record.link == nil && badgeTitle == nil ? .center : .top, spacing: 6) {
                if let toggle {
                    Button {
                        do { try toggle(nil) } catch { errorMessage = error.localizedDescription }
                    } label: {
                        Image(systemName: completed ? "checkmark.circle.fill" : record.subtasks.contains(where: \.isComplete) ? "circle.lefthalf.filled" : "circle")
                            .font(.title3)
                            .foregroundStyle(record.isUrgent || overdue ? Color.red : Color.accentColor)
                            .frame(width: taskCheckboxWidth, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!record.subtasks.isEmpty)
                    .accessibilityLabel(completed ? "Restore " + record.title : "Complete " + record.title)
                }
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Button(action: onEdit) {
                            HStack {
                                TaskTitle(title: record.title).strikethrough(completed)
                                TaskBadges(record: record)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .foregroundStyle(completed ? .secondary : .primary)
                        }
                        .buttonStyle(.plain)
                        if record.link != nil || badgeTitle != nil {
                            TaskListDetails(record: record, badgeTitle: badgeTitle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: onEdit) {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit " + record.title)
                }
            }
            if let toggle {
                ForEach(visibleSubtasks) { child in
                    Button {
                        do { try toggle(child.id) } catch { errorMessage = error.localizedDescription }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: child.isComplete ? "checkmark.circle.fill" : "circle")
                                .frame(width: 44, height: 44)
                            TaskTitle(title: child.title).strikethrough(child.isComplete)
                        }
                        .foregroundStyle(child.isComplete || completed ? Color.secondary : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(child.isComplete ? "Completed" : "Incomplete")
                    .padding(.leading, 24)
                }
            }
        }
        .listRowInsets(.vertical, 4)
        .alert("Couldn’t update task", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

private struct TaskTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TaskListDetails: View {
    let record: TaskRecord
    let badgeTitle: String?

    var body: some View {
        if record.link != nil || badgeTitle != nil {
            HStack(spacing: 8) {
                if let url = record.link { TaskLinkButton(url: url) }
                if let badgeTitle {
                    ListBadge(title: badgeTitle)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct TaskLinkButton: View {
    let url: URL

    var body: some View {
        Link(destination: url) {
            Label("Open Link", systemImage: "arrow.up.right.square")
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .accessibilityHint(url.host() ?? url.absoluteString)
    }
}

private struct TaskBadges: View {
    private var dateBadge = DateBadgePreferences()
    let record: TaskRecord
    var body: some View {
        HStack(spacing: 5) {
            if record.isUrgent {
                Image(systemName: "star.fill")
                    .foregroundStyle(record.completedAt == nil ? Color.orange : .secondary)
                    .accessibilityLabel("Urgent")
            }
            if record.repeatRule != RepeatRule.never.rawValue {
                Image(systemName: "repeat").accessibilityLabel("Repeating")
            }
            if dateBadge.isVisible, let day = record.dueDay {
                TaskDateBadge(day: day)
            }
        }
        .foregroundStyle(.secondary)
    }
}

#Preview { ContentView().modelContainer(for: [TaskRecord.self, CompletionArchive.self], inMemory: true) }

private struct NewTaskTagButton: View {
    @Environment(\.modelContext) private var context
    let list: TaskListRecord
    @State private var creating = false
    @State private var sessionID = UUID()

    var body: some View {
        Button("New Tag") {
            sessionID = UUID()
            creating = true
        }
            .sheet(isPresented: $creating) {
                TaskTagEditor(tags: list.tags) { tag in
                    list.tags.append(tag)
                    do { try context.save() }
                    catch { context.rollback(); throw error }
                }
                .id(sessionID)
            }
    }
}
