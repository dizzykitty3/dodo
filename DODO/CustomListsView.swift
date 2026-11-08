import SwiftData
import SwiftUI

struct CustomListsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: TaskGroup.displayOrder) private var groups: [TaskGroup]
    @State private var selection: TaskGroup?
    @State private var editingGroup: TaskGroup?
    @State private var creatingList = false
    @State private var deleting = false
    @State private var error: String?

    var body: some View {
        List {
            ForEach(groups) { group in
                Button {
                    editingGroup = group
                } label: {
                    HStack {
                        Image(systemName: group.cardIcon.rawValue).foregroundStyle(group.cardColor.color)
                        Text(group.name)
                        Spacer()
                        Image(systemName: "pencil").foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onMove { offsets, destination in
                var ordered = groups
                ordered.move(fromOffsets: offsets, toOffset: destination)
                save {
                    for (position, group) in ordered.enumerated() { group.position = position }
                }
            }
            .onDelete { offsets in
                guard let index = offsets.first else { return }
                selection = groups[index]
                deleting = true
            }
            Button("New List") { creatingList = true }
                .tint(.blue)
        }
        .navigationTitle("Manage Lists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !groups.isEmpty { EditButton() } }
        .sheet(isPresented: $creatingList) {
            NavigationStack { CustomListEditor() }
        }
        .sheet(item: $editingGroup) { group in
            NavigationStack { CustomListEditor(group: group) }
        }
        .alert("Delete List?", isPresented: $deleting) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let group = selection else { return }
                save {
                    let id = group.persistentModelID
                    let members = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.group?.persistentModelID == id })
                    for task in try context.fetch(members) { task.group = nil }
                    context.delete(group)
                }
                selection = nil
            }
        } message: {
            Text("Deleting this list keeps its tasks.")
        }
        .alert("Couldn’t Save Changes", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private func save(_ changes: () throws -> Void) {
        do {
            try changes()
            try context.save()
        } catch {
            context.rollback()
            self.error = error.localizedDescription
        }
    }
}
