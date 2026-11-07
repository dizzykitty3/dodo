import SwiftData
import SwiftUI

struct TaskEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let task: TaskRecord?
    @Query(sort: \TaskGroup.createdAt) private var groups: [TaskGroup]
    let presetGroup: TaskGroup?
    @State private var group: TaskGroup?
    let presetToday: Bool
    let presetUrgent: Bool
    @State private var initialDate: Date
    let onDelete: () -> Void
    let onCreate: () -> Void

    @State private var title: String
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var rule: RepeatRule
    @State private var weekday: Int
    @State private var monthDay: Int
    @State private var urgent: Bool
    @State private var subtasks: [Subtask]
    private enum Field: Hashable { case title, subtask(UUID) }
    @FocusState private var focusedField: Field?
    @State private var confirmingDiscard = false
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    init(task: TaskRecord? = nil, presetToday: Bool = false, presetUrgent: Bool = false, presetGroup: TaskGroup? = nil, onDelete: @escaping () -> Void = {}, onCreate: @escaping () -> Void = {}) {
        self.presetGroup = presetGroup
        _group = State(initialValue: task?.group ?? presetGroup)
        self.presetToday = presetToday
        self.presetUrgent = presetUrgent
        self.onDelete = onDelete
        self.onCreate = onCreate
        self.task = task
        let date = task?.dueDay.flatMap { try? TaskRecord.dayFormat.parseStrategy.parse($0) } ?? .now
        let rule = RepeatRule(rawValue: task?.repeatRule ?? "") ?? .never
        let calendar = Calendar(identifier: .gregorian)
        _title = State(initialValue: task?.title ?? "")
        _initialDate = State(initialValue: date)
        _date = State(initialValue: date)
        _hasDate = State(initialValue: task?.dueDay != nil || presetToday)
        _rule = State(initialValue: rule)
        _weekday = State(initialValue: (rule == .weekly ? task?.repeatDay : nil) ?? calendar.component(.weekday, from: date))
        _monthDay = State(initialValue: (rule == .monthly ? task?.repeatDay : nil) ?? calendar.component(.day, from: date))
        _urgent = State(initialValue: task?.isUrgent ?? presetUrgent)
        _subtasks = State(initialValue: task?.subtasks ?? [])
    }

    var body: some View {
        Form {
            Section("Task") {
                TextField("Title", text: $title)
                    .focused($focusedField, equals: .title)
                if !groups.isEmpty {
                    Picker("List", selection: $group) {
                        Text("None").tag(nil as TaskGroup?)
                        ForEach(groups) { Text($0.name).tag(Optional($0)) }
                    }
                }
                Toggle("Urgent", isOn: $urgent)
            }
            Section("Schedule") {
                Toggle("Set date", isOn: $hasDate)
                if hasDate { DatePicker("Date", selection: $date, displayedComponents: .date) }
                Picker("Repeat", selection: $rule) {
                    ForEach(RepeatRule.allCases, id: \.self) { Text($0.rawValue) }
                }
                if rule == .weekly {
                    Picker("On", selection: $weekday) {
                        ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                    }
                } else if rule == .monthly {
                    Stepper("Day of month: \(monthDay)", value: $monthDay, in: 1...31)
                }
            }
            Section("Subtasks") {
                ForEach($subtasks) { $subtask in
                    HStack {
                        Button {
                            subtask.isComplete.toggle()
                        } label: {
                            Image(systemName: subtask.isComplete ? "checkmark.circle.fill" : "circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(subtask.isComplete ? "Mark incomplete" : "Mark complete")
                        TextField("Subtask title", text: $subtask.title)
                            .focused($focusedField, equals: .subtask(subtask.id))
                            .submitLabel(.next)
                            .onSubmit {
                                guard !subtask.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                      let index = subtasks.firstIndex(where: { $0.id == subtask.id }) else { return }
                                insertSubtask(at: index + 1)
                            }
                    }
                }
                .onDelete { subtasks.remove(atOffsets: $0) }
                Button("Add subtask") {
                    insertSubtask(at: subtasks.endIndex)
                }
                .tint(.blue)
            }
            if task != nil {
                Button("Delete task", role: .destructive) { confirmingDelete = true }
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            if task == nil { focusedField = .title }
        }
        .navigationTitle(task == nil ? "New Task" : "Edit Task")
        .interactiveDismissDisabled(hasNewTaskChanges)
        .toolbar {
            if task == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        if hasNewTaskChanges { confirmingDiscard = true } else { dismiss() }
                    }
                    .confirmationDialog("Discard this task?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                        Button("Discard changes", role: .destructive) { dismiss() }
                        Button("Keep editing", role: .cancel) {}
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(cleanTitle.isEmpty)
            }
        }
        .confirmationDialog("Delete this task and its subtasks?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete task", role: .destructive) {
                guard let task else { return }
                task.deletedAt = .now
                commit(afterSave: onDelete)
            }
        }
        .alert("Couldn’t save changes", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var hasNewTaskChanges: Bool {
        task == nil && (!title.isEmpty || group != presetGroup || urgent != presetUrgent || hasDate != presetToday || (hasDate && !Calendar.current.isDate(date, inSameDayAs: initialDate)) || rule != .never || !subtasks.isEmpty)
    }

    private func insertSubtask(at index: Int) {
        let next = Subtask()
        subtasks.insert(next, at: index)
        focusedField = .subtask(next.id)
    }

    private var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !cleanTitle.isEmpty else { return }
        let record = task ?? TaskRecord(title: cleanTitle)
        if task == nil { context.insert(record) }
        record.title = cleanTitle
        record.dueDay = hasDate ? date.formatted(TaskRecord.dayFormat) : nil
        record.repeatRule = rule.rawValue
        record.repeatDay = rule == .weekly ? weekday : rule == .monthly ? monthDay : nil
        record.group = group
        record.isUrgent = urgent
        record.subtasks = subtasks.compactMap {
            var subtask = $0
            subtask.title = subtask.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return subtask.title.isEmpty ? nil : subtask
        }
        commit(afterSave: task == nil ? onCreate : {})
    }

    private func commit(afterSave: () -> Void) {
        do {
            try context.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            afterSave()
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
