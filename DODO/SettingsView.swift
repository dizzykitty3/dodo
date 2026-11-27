import SwiftUI

struct SettingsView: View {
    @Binding var previewLimit: Int
    @Binding var urgentPreviewLimit: Int
    @Binding var hideUndatedFromTodayPreview: Bool
    @Binding var sortScheduled: Bool
    @Binding var sortCompleted: Bool
    @AppStorage("completedCleanupInterval") private var cleanupInterval = CleanupInterval.never
    @AppStorage("trashRetention") private var trashRetention = TrashRetention.sevenDays
    @AppStorage("newTasksDueToday") private var newTasksDueToday = false
    @AppStorage("todayHideOlderCompletedSubtasks") private var hideOlderCompletedSubtasks = false
    @AppStorage("todayHideOldOverdue") private var hideOldOverdue = false
    @AppStorage("todayOverdueDays") private var overdueDays = 30
    @AppStorage("todayBeforeOverdue") private var todayBeforeOverdue = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var listBadge = ListBadgePreferences()
    var dateBadge = DateBadgePreferences()
    let completedCount: Int
    var onImport: () -> Void = {}

    var body: some View {
        Form {
            Section {
                NavigationLink("Tasks") { taskSettings }
                NavigationLink("Lists") { listSettings }
                NavigationLink("Interface") { interfaceSettings }
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

    private var taskSettings: some View {
        Form {
            Section {
                Toggle("Default Due Date to Today", isOn: $newTasksDueToday)
            } header: {
                Text("New Tasks")
            } footer: {
                Text("New tasks start with today’s date. You can change or remove it before saving.")
            }
            Section {
                Picker("Auto Clear", selection: $cleanupInterval) {
                    Text("Never").tag(CleanupInterval.never)
                    Text("After 1 day").tag(CleanupInterval.oneDay)
                    Text("After 7 days").tag(CleanupInterval.sevenDays)
                }
                Picker("Auto Delete", selection: $trashRetention) {
                    Text("Never").tag(TrashRetention.never)
                    Text("After 1 day").tag(TrashRetention.oneDay)
                    Text("After 7 days").tag(TrashRetention.sevenDays)
                    Text("After 1 month").tag(TrashRetention.oneMonth)
                }
            } header: {
                Text("Data Management")
            } footer: {
                Text("Auto Clear moves completed tasks to Recently Deleted after completion. Future repeat occurrences are kept. Auto Delete permanently deletes tasks after they enter Recently Deleted.")
            }
            DataTransferSection(onImport: onImport)
        }
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var listSettings: some View {
        ListsSettingsView(sortScheduled: $sortScheduled, sortCompleted: $sortCompleted)
    }

    private var interfaceSettings: some View {
        Form {
            Section {
                NavigationLink("Home Screen") { homeSettings }
            }
            Section {
                NavigationLink("Badge Settings") { badgeSettings }
            }
        }
        .navigationTitle("Interface")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var homeSettings: some View {
        Form {
            Section("Urgent Card") { previewLimitPicker($urgentPreviewLimit) }
            Section("Today Card") {
                previewLimitPicker($previewLimit)
                Toggle("Hide Tasks Without a Date", isOn: $hideUndatedFromTodayPreview)
            }
            Section {
                Toggle("Keep Only the Latest Completed Subtask", isOn: $hideOlderCompletedSubtasks)
                Toggle("Hide Older Overdue Tasks", isOn: $hideOldOverdue)
                if hideOldOverdue {
                    Stepper("Older Than \(overdueDays) Days", value: $overdueDays, in: 1...3650)
                }
                Toggle("Show Today Before Overdue", isOn: $todayBeforeOverdue)
            } header: {
                Text("Today Page")
            } footer: {
                Text("Unfinished subtasks stay visible. Hidden overdue tasks remain in other lists.")
            }
        }
        .navigationTitle("Home Screen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var badgeSettings: some View {
        Form {
            Section("List Badges") {
                Toggle("Show Tag Badges", isOn: listBadge.$isVisible)
                if listBadge.isVisible {
                    Picker("Content", selection: listBadge.$content) {
                        ForEach(ListBadgeContent.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    if listBadge.content == .both {
                        Picker("Separator", selection: listBadge.$separator) {
                            ForEach(ListBadgeSeparator.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    }
                }
            }
            Section("Date Badges") {
                Toggle("Show Date Badges", isOn: dateBadge.$isVisible)
                if dateBadge.isVisible {
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
                }
            }
            Section("Preview") {
                ZStack(alignment: .leading) {
                    badgePreview.id(previewIdentity).transition(.opacity)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: previewIdentity)
            }
        }
        .navigationTitle("Badge Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewIdentity: String {
        "\(listBadge.isVisible)|\(dateBadge.isVisible)|\(listBadge.content.rawValue)|\(listBadge.separator.rawValue)|\(dateBadge.order.rawValue)|\(dateBadge.separator.rawValue)|\(dateBadge.abbreviatesMonth)|\(dateBadge.showsCurrentYear)"
    }

    private var badgePreview: some View {
        let year = Calendar(identifier: .gregorian).component(.year, from: .now)
        return VStack(alignment: .leading, spacing: 20) {
            ForEach([year, year + 1], id: \.self) { year in
                VStack(alignment: .leading, spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text("Plan the next project")
                            if dateBadge.isVisible { TaskDateBadge(day: "\(year)-11-04") }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Plan the next project")
                            if dateBadge.isVisible { TaskDateBadge(day: "\(year)-11-04") }
                        }
                    }
                    if let title = listBadge.title(list: "Work", tag: "Planning") {
                        ListBadge(title: title)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
