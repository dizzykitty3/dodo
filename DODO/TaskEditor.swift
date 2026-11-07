import SwiftData
import SwiftUI

struct TaskEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let task: TaskRecord?

    @State private var title: String
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var rule: RepeatRule
    @State private var weekday: Int
    @State private var monthDay: Int
    @State private var urgent: Bool
    @State private var personal: Bool
    @State private var subtasks: [Subtask]
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    init(task: TaskRecord? = nil) {
        self.task = task
        let date = task?.dueDay.flatMap { try? TaskRecord.dayFormat.parseStrategy.parse($0) } ?? .now
        let rule = RepeatRule(rawValue: task?.repeatRule ?? "") ?? .never
        let calendar = Calendar(identifier: .gregorian)
        _title = State(initialValue: task?.title ?? "")
        _date = State(initialValue: date)
        _hasDate = State(initialValue: task?.dueDay != nil)
        _rule = State(initialValue: rule)
        _weekday = State(initialValue: (rule == .weekly ? task?.repeatDay : nil) ?? calendar.component(.weekday, from: date))
        _monthDay = State(initialValue: (rule == .monthly ? task?.repeatDay : nil) ?? calendar.component(.day, from: date))
        _urgent = State(initialValue: task?.isUrgent ?? false)
        _personal = State(initialValue: task?.isPersonal ?? false)
        _subtasks = State(initialValue: task?.subtasks ?? [])
    }

    var body: some View {
        Form {
            Section("Task") {
                TextField("Title", text: $title)
                Toggle("Urgent", isOn: $urgent)
                Toggle("Personal list", isOn: $personal)
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
                        .buttonStyle(.glass)
                        .accessibilityLabel(subtask.isComplete ? "Mark incomplete" : "Mark complete")
                        TextField("Subtask title", text: $subtask.title)
                    }
                }
                .onDelete { subtasks.remove(atOffsets: $0) }
                Button("Add subtask", systemImage: "plus") { subtasks.append(Subtask()) }
                    .buttonStyle(.glass)
            }
            if task != nil {
                Button("Delete task", role: .destructive) { confirmingDelete = true }
                    .buttonStyle(.glass)
            }
        }
        .navigationTitle(task == nil ? "New Task" : "Edit Task")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(cleanTitle.isEmpty)
            }
        }
        .confirmationDialog("Delete this task and its subtasks?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete task", role: .destructive) {
                guard let task else { return }
                context.delete(task)
                commit()
            }
        }
        .alert("Couldn’t save changes", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
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
        record.isUrgent = urgent
        record.isPersonal = personal
        record.subtasks = subtasks.compactMap {
            var subtask = $0
            subtask.title = subtask.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return subtask.title.isEmpty ? nil : subtask
        }
        commit()
    }

    private func commit() {
        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
