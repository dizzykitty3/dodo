import SwiftData
import SwiftUI

struct ListsSettingsView: View {
    @Binding var sortScheduled: Bool
    @Binding var sortCompleted: Bool
    @Environment(\.modelContext) private var context
    @Query(sort: TaskListRecord.displayOrder) private var lists: [TaskListRecord]
    @State private var selection: TaskListRecord?
    @State private var editingList: TaskListRecord?
    @State private var creatingList = false
    @State private var deleting = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("Sort Scheduled by Due Date", isOn: $sortScheduled)
                Toggle("Sort Completed by Completion Time", isOn: $sortCompleted)
            } header: {
                Text("List Sorting")
            } footer: {
                Text("Lists show newly created tasks first by default.")
            }
            Section {
                ForEach(lists) { list in
                    Button {
                        editingList = list
                    } label: {
                        HStack {
                            Image(systemName: list.cardIcon.rawValue).foregroundStyle(list.cardColor.color)
                            Text(list.name)
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onMove { offsets, destination in
                    var ordered = lists
                    ordered.move(fromOffsets: offsets, toOffset: destination)
                    save {
                        for (position, list) in ordered.enumerated() { list.position = position }
                    }
                }
                .onDelete { offsets in
                    guard let index = offsets.first else { return }
                    selection = lists[index]
                    deleting = true
                }
                Button("New List") { creatingList = true }
                    .tint(.blue)
            } header: {
                Text("Manage Lists")
            } footer: {
                if lists.isEmpty {
                    Text("Your custom task lists appear here. Tap New List to create one.")
                } else {
                    Text("Tap a list to edit. Drag to reorder or swipe to delete.")
                }
            }
        }
        .navigationTitle("Lists")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creatingList) {
            NavigationStack { CustomListEditor() }
                .confirmSheetDismissal()
        }
        .sheet(item: $editingList) { list in
            NavigationStack { CustomListEditor(list: list) }
                .confirmSheetDismissal()
        }
        .alert("Delete List?", isPresented: $deleting) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let list = selection else { return }
                save { try list.deleteKeepingTasks(in: context) }
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
