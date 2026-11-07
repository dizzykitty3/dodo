import SwiftUI
import SwiftData

private enum TaskList: String, CaseIterable, Identifiable {
    case today = "Today", urgent = "Urgent", completed = "Completed"
    case scheduled = "Scheduled", all = "All Tasks"

    var isCompact: Bool { self == .all || self == .completed }

    var id: Self { self }
    var color: Color {
        switch self {
        case .all: Color(red: 0.37, green: 0.39, blue: 0.44)
        case .today: Color(red: 0.35, green: 0.56, blue: 0.72)
        case .urgent: Color(red: 0.73, green: 0.39, blue: 0.54)
        case .completed: Color(red: 0.46, green: 0.50, blue: 0.53)
        case .scheduled: Color(red: 0.74, green: 0.44, blue: 0.44)
        }
    }
    var symbol: String {
        switch self {
        case .all: "tray.full.fill"
        case .today: "sun.max.fill"
        case .urgent: "star.fill"
        case .completed: "checkmark"
        case .scheduled: "calendar"
        }
    }
}

private enum Panel: Identifiable, Hashable {
    case search, settings, compose
    var id: Self { self }
}

struct ContentView: View {
    @AppStorage("todayPreviewLimit") private var todayPreviewLimit = 5
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var tasks: [TaskRecord]
    @State private var composeSource: TaskList?
    @State private var composingFromSearch = false
    @State private var panel: Panel?
    @Environment(\.modelContext) private var context
    @State private var pendingRemoval: [PersistentIdentifier: Date] = [:]
    @State private var didCreateTask = false
    @State private var toastMessage = ""
    @State private var toastID: UUID?
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    card(.today)
                    HStack(spacing: 12) {
                        card(.urgent)
                        card(.scheduled)
                    }
                    card(.all)
                    card(.completed)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("DODO")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Search", systemImage: "magnifyingglass") {
                        query = ""
                        panel = .search
                    }
                    .labelStyle(.iconOnly)
                    Button("Settings", systemImage: "gearshape") { panel = .settings }
                        .labelStyle(.iconOnly)
                }
                composeToolbar(from: nil)
            }
            .navigationDestination(for: TaskList.self) { list in
                taskRows(items(list, includePending: true))
                    .navigationTitle(list.rawValue)
                    .toolbar(.visible, for: .navigationBar)
                    .toolbar { if list != .completed { composeToolbar(from: list) } }
            }
        }
        .overlay { toastPill }
        .task(id: toastID) {
            guard toastID != nil else { return }
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            toastID = nil
        }
        .sheet(item: $panel, onDismiss: finishCompose) { selected in
            NavigationStack {
                Group {
                    switch selected {
                    case .search:
                        let matches = tasks.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
                        taskRows(matches, showsCheckbox: false)
                            .overlay {
                                if matches.isEmpty { ContentUnavailableView.search(text: query) }
                            }
                            .navigationTitle("Search")
                            .toolbar { composeToolbar(from: nil, inSearch: true) }
                            .sheet(isPresented: $composingFromSearch, onDismiss: finishCompose) {
                                NavigationStack { TaskEditor(onCreate: { didCreateTask = true }) }
                                    .presentationDetents([.large])
                            }
                            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search tasks")
                    case .settings:
                        SettingsView(previewLimit: $todayPreviewLimit, completedCount: items(.completed).count)
                    case .compose:
                        TaskEditor(presetToday: composeSource == .today, presetUrgent: composeSource == .urgent,
                                   onCreate: { didCreateTask = true })
                    }
                }
                .toolbar {
                    if selected != .compose {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") { panel = nil }
                        }
                    }
                }
            }
            .overlay { if selected == .search { toastPill } }
            .presentationDetents([.large])
        }
    }

    private func finishCompose() {
        if didCreateTask {
            didCreateTask = false
            showToast("Task saved")
        }
    }

    @ToolbarContentBuilder
    private func composeToolbar(from source: TaskList?, inSearch: Bool = false) -> some ToolbarContent {
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button("New Task", systemImage: "square.and.pencil") {
                composeSource = source
                if inSearch { composingFromSearch = true } else { panel = .compose }
            }
            .labelStyle(.iconOnly)
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

    private func taskRows(_ records: [TaskRecord], showsCheckbox: Bool = true) -> some View {
        List(records) { record in
            CompletionRow(record: record, onDelete: { showToast("Task deleted") },
                          toggle: showsCheckbox ? { try toggleCompletion(record) } : nil)
        }
    }

    private func toggleCompletion(_ record: TaskRecord) throws {
        let id = record.persistentModelID
        let previous = record.completedAt
        let completion = previous == nil ? Date.now : nil
        record.completedAt = completion
        do {
            try context.save()
        } catch {
            record.completedAt = previous
            throw error
        }
        UISelectionFeedbackGenerator().selectionChanged()
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
            if list == .completed { return task.completedAt != nil }
            guard task.completedAt == nil || (includePending && pendingRemoval[task.persistentModelID] == task.completedAt) else { return false }
            switch list {
            case .all: return true
            case .today: return task.dueDay.map { $0 <= today } ?? true
            case .urgent: return task.isUrgent
            case .scheduled: return task.dueDay != nil
            case .completed: return false
            }
        }
    }

    private func card(_ list: TaskList) -> some View {
        let entries = items(list)
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return NavigationLink(value: list) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    Image(systemName: list.symbol).font(.title3.weight(.semibold))
                    if list == .today { Text("Today").font(.title2.bold()) }
                    if list.isCompact { Text(list.rawValue).font(.headline) }
                    Spacer(minLength: 2)
                    Text("\(entries.count)").font(.title.bold()).monospacedDigit()
                }
                if list == .today {
                    ForEach(entries.prefix(todayPreviewLimit == -1 ? entries.count : max(0, todayPreviewLimit))) { task in
                        Divider().overlay(.white.opacity(0.25))
                        HStack(spacing: 10) {
                            Image(systemName: "circle").foregroundStyle(.white.opacity(0.7))
                            Text(task.title).font(.body)
                        }
                    }
                } else if !list.isCompact {
                    Text(list.rawValue).font(.headline)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, list == .today ? 20 : 16)
            .padding(.vertical, list.isCompact ? 8 : list == .today ? 20 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(list.color.gradient, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

private struct CompletionRow: View {
    @Environment(\.modelContext) private var context
    let record: TaskRecord
    let onDelete: () -> Void
    let toggle: (() throws -> Void)?
    @State private var errorMessage: String?

    var body: some View {
        let completed = record.completedAt != nil
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if let toggle {
                    Button {
                        do { try toggle() } catch { errorMessage = error.localizedDescription }
                    } label: {
                        Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(completed ? "Restore " + record.title : "Complete " + record.title)
                }
                NavigationLink {
                    TaskEditor(task: record, onDelete: onDelete)
                } label: {
                    HStack {
                        Text(record.title).fontWeight(record.subtasks.isEmpty ? .regular : .semibold).strikethrough(completed)
                        if record.isUrgent {
                            Image(systemName: "star.fill")
                                .foregroundStyle(completed ? Color.secondary : .orange)
                                .accessibilityLabel("Urgent")
                        }
                        if record.repeatRule != RepeatRule.never.rawValue {
                            Image(systemName: "repeat").foregroundStyle(.secondary).accessibilityLabel("Repeating")
                        }
                    }
                    .foregroundStyle(completed ? .secondary : .primary)
                }
            }
            if toggle != nil {
                ForEach(record.subtasks) { child in
                    Button {
                        guard let index = record.subtasks.firstIndex(where: { $0.id == child.id }) else { return }
                        let previous = record.subtasks
                        record.subtasks[index].isComplete.toggle()
                        do {
                            try context.save()
                            UISelectionFeedbackGenerator().selectionChanged()
                        } catch {
                            record.subtasks = previous
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: child.isComplete ? "checkmark.circle.fill" : "circle")
                                .frame(width: 44, height: 44)
                            Text(child.title).strikethrough(child.isComplete)
                        }
                        .foregroundStyle(child.isComplete || completed ? Color.secondary : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(child.isComplete ? "Completed" : "Incomplete")
                    .padding(.leading, 24)
                }
            }
        }
        .alert("Couldn’t update task", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

#Preview { ContentView().modelContainer(for: TaskRecord.self, inMemory: true) }
