import SwiftUI

enum ListBadgeContent: String, CaseIterable {
    case list = "List Name", tag = "Tag Name", both = "List + Tag"

    static func migratedValue(_ value: String) -> String {
        switch value {
        case "Group Name": tag.rawValue
        case "List + Group": both.rawValue
        default: value
        }
    }
}

enum ListBadgeSeparator: String, CaseIterable {
    case none = "None", space = "Space", hyphen = "Hyphen", colon = "Colon", slash = "Slash"

    var text: String {
        switch self {
        case .none: ""
        case .space: " "
        case .hyphen: " - "
        case .colon: ": "
        case .slash: " / "
        }
    }
}

struct ListBadgePreferences: DynamicProperty {
    @AppStorage("listBadgeContent") var content = ListBadgeContent.list
    @AppStorage("listBadgeSeparator") var separator = ListBadgeSeparator.space

    func title(list: String, tag: String?) -> String? {
        switch content {
        case .list: list
        case .tag: tag
        case .both: tag.map { list + separator.text + $0 } ?? list
        }
    }

    func title(for record: TaskRecord) -> String? {
        guard let list = record.list else { return nil }
        let tag = record.tagID.flatMap { id in list.tags.first { $0.id == id }?.name }
        return title(list: list.name, tag: tag)
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
