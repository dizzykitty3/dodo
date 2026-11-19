import SwiftUI

struct TaskTagEditor: View {
    @Environment(\.dismiss) private var dismiss
    let tag: TaskTag?
    let tags: [TaskTag]
    let save: (TaskTag) throws -> Void
    @State private var name: String
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    init(tag: TaskTag? = nil, tags: [TaskTag], save: @escaping (TaskTag) throws -> Void) {
        self.tag = tag
        self.tags = tags
        self.save = save
        _name = State(initialValue: tag?.name ?? "")
    }

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let duplicate = tags.contains { $0.id != tag?.id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        NavigationStack {
            Form {
                TextField("Tag name", text: $name).focused($focused)
                if duplicate { Text("A tag with this name already exists in this list.").foregroundStyle(.secondary) }
            }
            .navigationTitle(tag == nil ? "New Tag" : "Edit Tag")
            .confirmUnsavedChanges(name != (tag?.name ?? ""))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tag == nil ? "Create" : "Save") {
                        do {
                            try save(TaskTag(id: tag?.id ?? UUID(), name: trimmed))
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .disabled(trimmed.isEmpty || duplicate)
                }
            }
            .onAppear { focused = true }
            .alert("Couldn’t Save Tag", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") {}
            } message: { Text(errorMessage ?? "") }
        }
        .confirmSheetDismissal()
        .presentationDetents([.large])
    }
}
