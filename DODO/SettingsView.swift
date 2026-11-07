import SwiftUI

struct SettingsView: View {
    @Binding var previewLimit: Int
    let completedCount: Int

    var body: some View {
        Form {
            Section("Today Card") {
                Picker("Task Preview Limit", selection: $previewLimit) {
                    ForEach(0...5, id: \.self) { limit in
                        Text(limit.formatted()).tag(limit)
                    }
                    Text("Unlimited").tag(-1)
                }
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

    private var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
