import SwiftUI

struct SettingsView: View {
    @Binding var previewLimit: Int
    @Binding var urgentPreviewLimit: Int
    let completedCount: Int

    var body: some View {
        Form {
            previewSection("Urgent Card", limit: $urgentPreviewLimit)
            previewSection("Today Card", limit: $previewLimit)

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
