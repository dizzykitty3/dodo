import SwiftData
import SwiftUI

struct BulkTaskActions: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [TaskRecord]
    let permanently: Bool
    let onSuccess: (String) -> Void
    @State private var confirming = false
    @State private var errorMessage: String?

    private var count: Int {
        tasks.filter { permanently ? $0.deletedAt != nil : $0.completedAt != nil && $0.deletedAt == nil }.count
    }
    private var actionTitle: String { permanently ? "Permanently Delete All" : "Delete All" }

    var body: some View {
        Menu {
            Button(actionTitle, role: .destructive) { confirming = true }
                .disabled(count == 0)
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .labelStyle(.iconOnly)
        .alert(permanently ? "Permanently delete all recently deleted tasks?" : "Delete all completed tasks?",
               isPresented: $confirming) {
            Button("Cancel", role: .cancel) {}
            Button(actionTitle, role: .destructive) {
                do {
                    let deleted = try CompletedTaskCleanup.deleteAll(permanently: permanently, context: context)
                    if deleted > 0 {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onSuccess(permanently ? "Tasks permanently deleted" : "Tasks moved to Recently Deleted")
                    }
                } catch { errorMessage = error.localizedDescription }
            }
        } message: {
            Text(permanently
                 ? "All \(count) tasks in Recently Deleted will be permanently deleted. This cannot be undone."
                 : "All \(count) completed tasks will move to Recently Deleted. You can restore them there.")
        }
        .alert("Couldn’t Delete Tasks", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: { Text(errorMessage ?? "") }
    }
}
