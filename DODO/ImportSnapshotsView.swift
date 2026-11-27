import SwiftData
import SwiftUI

struct ImportSnapshotsView: View {
    @Environment(\.modelContext) private var context
    let onRestore: () -> Void
    private let store = ImportSnapshots()
    @State private var entries: [ImportSnapshots.Entry] = []
    @State private var restoring: ImportSnapshots.Entry?
    @State private var deleting: ImportSnapshots.Entry?
    @State private var confirmingRestore = false
    @State private var confirmingDelete = false
    @State private var errorMessage: String?
    @State private var restored = false

    var body: some View {
        List {
            if !entries.isEmpty {
                Section {
                    ForEach(entries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.date.formatted(date: .numeric, time: .standard))
                                Text(entry.taskCount.map { "\($0.formatted()) tasks" } ?? "Snapshot unavailable")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button("Restore", systemImage: "arrow.counterclockwise") { restoring = entry; confirmingRestore = true }
                                    .disabled(entry.taskCount == nil)
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = entry; confirmingDelete = true }
                            } label: {
                                Label("Snapshot Actions", systemImage: "ellipsis")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.glass)
                        }
                    }
                } footer: {
                    Text("Task counts include Recently Deleted. Restoring replaces all current data and settings. Snapshots are kept until you delete them.")
                }
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("No Import Snapshots", systemImage: "clock.arrow.circlepath",
                    description: Text("A snapshot of your data and settings is saved before every import. Import a DODO backup from Settings to get started."))
            }
        }
        .navigationTitle("Import Snapshots")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .alert("Restore Snapshot?", isPresented: $confirmingRestore) {
            Button("Cancel", role: .cancel) { restoring = nil }
            Button("Restore", role: .destructive) {
                guard let entry = restoring else { return }
                perform {
                    try store.restore(entry, context: context)
                    onRestore()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    restored = true
                }
                restoring = nil
            }
        } message: {
            if let entry = restoring {
                Text("Restore \(entry.date.formatted(date: .numeric, time: .standard)) with \((entry.taskCount ?? 0).formatted()) tasks? All current data and settings will be replaced, including changes made after importing. A snapshot of your current state will be saved first.")
            }
        }
        .alert("Delete Snapshot?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                guard let entry = deleting else { return }
                perform { try store.delete(entry) }
                deleting = nil
            }
        } message: {
            Text("This permanently deletes this snapshot. Your current tasks and settings are not affected.")
        }
        .alert("Snapshot Restored", isPresented: $restored) { Button("OK") {} }
        .alert("Couldn’t Update Snapshots", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: { Text(errorMessage ?? "") }
    }

    private func reload() {
        do { entries = try store.entries() }
        catch { errorMessage = error.localizedDescription }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); reload() }
        catch { errorMessage = error.localizedDescription }
    }
}
