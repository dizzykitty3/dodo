import SwiftUI

enum ListBadgeContent: String, CaseIterable {
    case list = "List Name", group = "Group Name", both = "List + Group"
}

enum ListBadgeSeparator: String, CaseIterable {
    case none = "None", space = "Space", hyphen = "Hyphen", colon = "Colon", slash = "Slash"

    var text: String {
        switch self {
        case .none: ""
        case .space: " "
        case .hyphen: "-"
        case .colon: ": "
        case .slash: " / "
        }
    }
}

struct ListBadgePreferences: DynamicProperty {
    @AppStorage("listBadgeContent") var content = ListBadgeContent.list
    @AppStorage("listBadgeSeparator") var separator = ListBadgeSeparator.space

    func title(list: String, group: String?) -> String? {
        switch content {
        case .list: list
        case .group: group
        case .both: group.map { list + separator.text + $0 } ?? list
        }
    }

    func title(for record: TaskRecord) -> String? {
        guard let list = record.group else { return nil }
        let group = record.sectionID.flatMap { id in list.sections.first { $0.id == id }?.name }
        return title(list: list.name, group: group)
    }
}

struct ListBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}
