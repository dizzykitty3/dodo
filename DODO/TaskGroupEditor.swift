import SwiftUI

struct TaskGroupEditor: View {
    @Environment(\.dismiss) private var dismiss
    let section: TaskListSection?
    let sections: [TaskListSection]
    let save: (TaskListSection) throws -> Void
    @State private var name: String
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    init(section: TaskListSection? = nil, sections: [TaskListSection], save: @escaping (TaskListSection) throws -> Void) {
        self.section = section
        self.sections = sections
        self.save = save
        _name = State(initialValue: section?.name ?? "")
    }

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let duplicate = sections.contains { $0.id != section?.id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        NavigationStack {
            Form {
                TextField("Group name", text: $name).focused($focused)
                if duplicate { Text("A group with this name already exists in this list.").foregroundStyle(.secondary) }
            }
            .navigationTitle(section == nil ? "New Group" : "Edit Group")
            .confirmUnsavedChanges(name != (section?.name ?? ""))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(section == nil ? "Create" : "Save") {
                        do {
                            try save(TaskListSection(id: section?.id ?? UUID(), name: trimmed))
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .disabled(trimmed.isEmpty || duplicate)
                }
            }
            .onAppear { focused = true }
            .alert("Couldn’t Save Group", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") {}
            } message: { Text(errorMessage ?? "") }
        }
        .confirmSheetDismissal()
        .presentationDetents([.large])
    }
}
