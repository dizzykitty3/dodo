import SwiftUI

struct SettingsView: View {
    @Binding var previewLimit: Int
    @Binding var urgentPreviewLimit: Int
    @Binding var hideUndatedFromTodayPreview: Bool
    @Binding var sortScheduled: Bool
    @Binding var sortCompleted: Bool
    @AppStorage("completedCleanupInterval") private var cleanupInterval = CleanupInterval.never
    @AppStorage("trashRetention") private var trashRetention = TrashRetention.sevenDays
    var dateBadge = DateBadgePreferences()
    let completedCount: Int

    var body: some View {
        Form {
            Section("Urgent Card") { previewLimitPicker($urgentPreviewLimit) }
            Section("Today Card") {
                previewLimitPicker($previewLimit)
                Toggle("Hide Tasks Without a Date", isOn: $hideUndatedFromTodayPreview)
            }

            Section {
                Toggle("Sort Scheduled by Due Date", isOn: $sortScheduled)
                Toggle("Sort Completed by Completion Time", isOn: $sortCompleted)
            } header: {
                Text("List Sorting")
            } footer: {
                Text("Lists show newly created tasks first by default.")
            }

            Section("Custom Lists") {
                NavigationLink("Manage Lists") { CustomListsView() }
            }

            Section("Date Badges") {
                Toggle("Use Abbreviated Month Names", isOn: dateBadge.$abbreviatesMonth)
                if !dateBadge.abbreviatesMonth {
                    Picker("Date Order", selection: dateBadge.$order) {
                        ForEach(DateBadgeOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Separator", selection: dateBadge.$separator) {
                        ForEach(DateBadgeSeparator.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                Toggle("Show Current Year", isOn: dateBadge.$showsCurrentYear)
                let year = Calendar(identifier: .gregorian).component(.year, from: .now)
                LabeledContent("Preview") {
                    HStack {
                        TaskDateBadge(day: "\(year)-11-04")
                        TaskDateBadge(day: "\(year + 1)-11-04")
                    }
                }
            }

            Section {
                Picker("Auto Clear", selection: $cleanupInterval) {
                    Text("Never").tag(CleanupInterval.never)
                    Text("After 1 day").tag(CleanupInterval.oneDay)
                    Text("After 7 days").tag(CleanupInterval.sevenDays)
                }
            } header: {
                Text("Completed Tasks")
            } footer: {
                Text("Move tasks to Recently Deleted after the selected time has passed since completion. Future repeat occurrences are kept.")
            }

            Section {
                Picker("Auto Delete", selection: $trashRetention) {
                    Text("Never").tag(TrashRetention.never)
                    Text("After 1 day").tag(TrashRetention.oneDay)
                    Text("After 7 days").tag(TrashRetention.sevenDays)
                    Text("After 1 month").tag(TrashRetention.oneMonth)
                }
            } header: {
                Text("Recently Deleted")
            } footer: {
                Text("Permanently delete tasks after the selected time has passed since they entered Recently Deleted.")
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

    private func previewLimitPicker(_ limit: Binding<Int>) -> some View {
        Picker("Task Preview Limit", selection: limit) {
            ForEach(0...5, id: \.self) { Text($0.formatted()).tag($0) }
            Text("Unlimited").tag(-1)
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
