import SwiftData
import SwiftUI

enum ListCardColor: String, CaseIterable {
    case indigo = "Indigo", blue = "Blue", teal = "Teal", green = "Green"
    case rose = "Rose", plum = "Plum", amber = "Amber", slate = "Slate"

    var color: Color {
        switch self {
        case .indigo: .indigo
        case .blue: Color(red: 0.26, green: 0.45, blue: 0.64)
        case .teal: Color(red: 0.22, green: 0.49, blue: 0.51)
        case .green: Color(red: 0.33, green: 0.49, blue: 0.35)
        case .rose: Color(red: 0.65, green: 0.35, blue: 0.44)
        case .plum: Color(red: 0.53, green: 0.36, blue: 0.57)
        case .amber: Color(red: 0.62, green: 0.43, blue: 0.24)
        case .slate: Color(red: 0.36, green: 0.41, blue: 0.48)
        }
    }
}

enum ListCardIcon: String, CaseIterable {
    case list = "list.bullet", home = "house.fill", work = "briefcase.fill"
    case shopping = "cart.fill", books = "book.fill", travel = "airplane"
    case health = "heart.fill", study = "graduationcap.fill", ideas = "lightbulb.fill"
    case nature = "leaf.fill", music = "music.note", fitness = "figure.walk"
}

extension TaskGroup {
    var cardColor: ListCardColor { ListCardColor(rawValue: colorName) ?? .indigo }
    var cardIcon: ListCardIcon { ListCardIcon(rawValue: symbolName) ?? .list }
}

struct CustomListEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: TaskGroup.displayOrder) private var groups: [TaskGroup]
    let group: TaskGroup?
    @FocusState private var nameFocused: Bool
    @State private var name: String
    @State private var color: ListCardColor
    @State private var icon: ListCardIcon
    @State private var error: String?

    @State private var sections: [TaskListSection]
    @State private var originalSectionIDs: Set<UUID>
    @State private var addingSection = false
    @State private var sectionName = ""
    @State private var confirmingDelete = false
    let onDelete: () -> Void

    init(group: TaskGroup? = nil, onDelete: @escaping () -> Void = {}) {
        self.onDelete = onDelete
        self.group = group
        _sections = State(initialValue: group?.sections ?? [])
        _originalSectionIDs = State(initialValue: Set(group?.sections.map(\.id) ?? []))
        _name = State(initialValue: group?.name ?? "")
        _color = State(initialValue: group?.cardColor ?? .indigo)
        _icon = State(initialValue: group?.cardIcon ?? .list)
    }

    private var trimmedSectionName: String { sectionName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var duplicateName: Bool {
        func matches(_ other: String) -> Bool {
            trimmedName.caseInsensitiveCompare(other.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        }
        return TaskList.builtIns.contains { matches($0.title) } ||
            groups.contains { $0.persistentModelID != group?.persistentModelID && matches($0.name) }
    }
    private var canSave: Bool { !trimmedName.isEmpty && !duplicateName }

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        Form {
            Section {
                Label(trimmedName.isEmpty ? "New List" : trimmedName, systemImage: icon.rawValue)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(color.color.gradient, in: RoundedRectangle(cornerRadius: 20))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                TextField("List name", text: $name)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { nameFocused = false }
            } header: {
                Text("Title")
            } footer: {
                if duplicateName { Text("A list with this name already exists.") }
            }
            Section("Card Color") {
                LazyVGrid(columns: columns) {
                    ForEach(ListCardColor.allCases, id: \.self) { option in
                        Button { color = option } label: {
                            Circle().fill(option.color)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if color == option { Image(systemName: "checkmark").foregroundStyle(.white) }
                                }
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel(option.rawValue)
                        .accessibilityAddTraits(color == option ? .isSelected : [])
                    }
                }
            }
            Section("Icon") {
                LazyVGrid(columns: columns) {
                    ForEach(ListCardIcon.allCases, id: \.self) { option in
                        Button { icon = option } label: {
                            Image(systemName: option.rawValue)
                                .frame(width: 44, height: 44)
                                .foregroundStyle(icon == option ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(icon == option ? color.color : nil).interactive(), in: .circle)
                        .accessibilityLabel(String(describing: option).capitalized)
                        .accessibilityAddTraits(icon == option ? .isSelected : [])
                    }
                }
            }
            Section {
                ForEach(sections) { section in Text(section.name) }
                    .onMove { sections.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { sections.remove(atOffsets: $0) }
                Button("New Group") { sectionName = ""; addingSection = true }
                    .tint(.blue)
                    .alert("New Group", isPresented: $addingSection) {
                        TextField("Group name", text: $sectionName)
                        Button("Cancel", role: .cancel) {}
                        Button("Add") {
                            sections.append(TaskListSection(name: trimmedSectionName))
                        }
                        .disabled(trimmedSectionName.isEmpty || sections.contains {
                            $0.name.caseInsensitiveCompare(trimmedSectionName) == .orderedSame
                        })
                    }
            } header: {
                Text("Groups")
            } footer: {
                if !sections.isEmpty { Text("Drag to reorder or swipe to delete. Tasks in a deleted group stay in this list under None.") }
            }
            if let group {
                Section {
                    Button("Delete List", role: .destructive) { confirmingDelete = true }
                        .confirmationDialog("Delete this list?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete List", role: .destructive) {
                                do {
                                    try group.deleteKeepingTasks(in: context)
                                    try context.save()
                                    dismiss()
                                    onDelete()
                                } catch {
                                    context.rollback()
                                    self.error = error.localizedDescription
                                }
                            }
                        } message: {
                            Text("Deleting this list keeps its tasks.")
                        }
                }
            }
        }
        .onAppear { if group == nil { nameFocused = true } }
        .navigationTitle(group == nil ? "New List" : "Edit List")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(group == nil ? "Create" : "Save") { save() }.disabled(!canSave)
            }
        }
        .alert("Couldn’t Save List", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private func save() {
        guard canSave else { return }
        let list = group ?? TaskGroup(name: trimmedName, position: (groups.last?.position ?? -1) + 1)
        if group == nil { context.insert(list) }
        list.name = trimmedName
        list.colorName = color.rawValue
        list.symbolName = icon.rawValue
        do {
            try list.applySectionEdits(sections, originalIDs: originalSectionIDs, in: context)
            try context.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            context.rollback()
            self.error = error.localizedDescription
        }
    }
}
