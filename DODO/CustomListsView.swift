import SwiftData
import SwiftUI

struct ListsSettingsView: View {
    @Binding var sortScheduled: Bool
    @Binding var sortCompleted: Bool
    @Environment(\.modelContext) private var context
    @Query(sort: TaskListRecord.displayOrder) private var lists: [TaskListRecord]
    @Query private var tasks: [TaskRecord]
    @State private var confirmingCleanup = false
    @State private var cleaned = false
    private var emptyItems: EmptyListCleanup.Candidates {
        EmptyListCleanup.candidates(lists: lists, tasks: tasks)
    }
    @State private var selection: TaskListRecord?
    @State private var editingList: TaskListRecord?
    @State private var creatingList = false
    @State private var listSessionID = UUID()
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
                            ListSymbol(name: list.cardIcon.rawValue).foregroundStyle(list.cardColor.color)
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
                Button("New List") {
                    listSessionID = UUID()
                    creatingList = true
                }
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
            Section {
                Button("Delete Empty Lists and Tags", role: .destructive) { confirmingCleanup = true }
                    .disabled(emptyItems.isEmpty)
            } header: {
                Text("Cleanup")
            } footer: {
                Text("Permanently deletes lists and tags with no tasks. Completed and recently deleted tasks count as tasks.")
            }
        }
        .navigationTitle("Lists")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creatingList) {
            NavigationStack { CustomListEditor() }
                .id(listSessionID)
                .confirmSheetDismissal()
        }
        .sheet(item: $editingList) { list in
            NavigationStack { CustomListEditor(list: list) }
                .confirmSheetDismissal()
                .presentationDetents([.large])
        }
        .alert("Delete Empty Lists and Tags?", isPresented: $confirmingCleanup) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                do {
                    try EmptyListCleanup.delete(in: context)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    cleaned = true
                } catch { self.error = error.localizedDescription }
            }
        } message: {
            Text("This permanently deletes \(emptyItems.lists.count) empty lists and \(emptyItems.tagCount) empty tags. Tasks are kept. This cannot be undone.")
        }
        .alert("Cleanup Complete", isPresented: $cleaned) {
            Button("OK") {}
        } message: {
            Text("Empty lists and tags have been deleted.")
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
