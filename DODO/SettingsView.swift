import SwiftUI

struct SettingsView: View {
    @Binding var previewLimit: Int
    @Binding var urgentPreviewLimit: Int
    @Binding var sortScheduled: Bool
    @Binding var sortCompleted: Bool
    @AppStorage("completedCleanupInterval") private var cleanupInterval = CleanupInterval.never
    let completedCount: Int

    var body: some View {
        Form {
            previewSection("Urgent Card", limit: $urgentPreviewLimit)
            previewSection("Today Card", limit: $previewLimit)

            Section("List Sorting") {
                Toggle("Sort Scheduled by Due Date", isOn: $sortScheduled)
                Toggle("Sort Completed by Completion Time", isOn: $sortCompleted)
            }

            Section {
                Picker("Auto-delete", selection: $cleanupInterval) {
                    Text("Never").tag(CleanupInterval.never)
                    Text("After 1 day").tag(CleanupInterval.oneDay)
                    Text("After 7 days").tag(CleanupInterval.sevenDays)
                }
            } header: {
                Text("Completed Tasks")
            } footer: {
                Text("Completed tasks are permanently deleted after the selected time. Future repeat occurrences are kept.")
            }

            Section("Stats & About") {
                LabeledContent("Tasks Completed", value: completedCount.formatted())
                LabeledContent("Version", value: version)
                Link("GitHub Repository", destination: URL(string: "https://github.com/dizzykitty3/dodo")!)
                Button("Open App Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
        }
        .navigationTitle("Settings")
    }

    private func previewSection(_ title: String, limit: Binding<Int>) -> some View {
        Section(title) {
            Picker("Task Preview Limit", selection: limit) {
                ForEach(0...5, id: \.self) { Text($0.formatted()).tag($0) }
                Text("Unlimited").tag(-1)
            }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
