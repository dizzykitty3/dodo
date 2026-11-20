import SwiftData
import SwiftUI

enum ListCardColor: String, CaseIterable {
    case indigo = "Indigo", blue = "Blue", teal = "Teal", green = "Green"
    case rose = "Rose", plum = "Plum", amber = "Amber", slate = "Slate"
    case brick = "Brick", coral = "Coral", ochre = "Ochre", olive = "Olive"
    case pine = "Pine", navy = "Navy", violet = "Violet", cocoa = "Cocoa"

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
        case .brick: Color(red: 0.57, green: 0.24, blue: 0.23)
        case .coral: Color(red: 0.70, green: 0.37, blue: 0.29)
        case .ochre: Color(red: 0.55, green: 0.44, blue: 0.14)
        case .olive: Color(red: 0.43, green: 0.47, blue: 0.23)
        case .pine: Color(red: 0.17, green: 0.37, blue: 0.29)
        case .navy: Color(red: 0.19, green: 0.29, blue: 0.46)
        case .violet: Color(red: 0.43, green: 0.32, blue: 0.63)
        case .cocoa: Color(red: 0.46, green: 0.34, blue: 0.29)
        }
    }
}

enum ListCardIcon: String, CaseIterable {
    case list = "list.bullet", home = "house.fill", work = "briefcase.fill"
    case shopping = "cart.fill", books = "book.fill", travel = "airplane"
    case health = "heart.fill", study = "graduationcap.fill", ideas = "lightbulb.fill"
    case nature = "leaf.fill", music = "music.note", fitness = "figure.walk"
    case meals = "fork.knife", coffee = "cup.and.saucer.fill", pets = "pawprint.fill"
    case family = "person.2.fill", gifts = "gift.fill", birthdays = "birthday.cake.fill"
    case budget = "creditcard.fill", errands = "basket.fill", car = "car.fill"
    case cycling = "bicycle", places = "mappin.and.ellipse", trips = "suitcase.fill"
    case photos = "camera.fill", movies = "film.fill", games = "gamecontroller.fill"
    case art = "paintpalette.fill", projects = "hammer.fill", coding = "laptopcomputer"
    case mail = "envelope.fill", appointments = "calendar", goals = "target"
    case running = "figure.run", sleep = "bed.double.fill", medicine = "pills.fill"
}

extension TaskListRecord {
    var cardColor: ListCardColor { ListCardColor(rawValue: colorName) ?? .indigo }
    var cardIcon: ListCardIcon { ListCardIcon(rawValue: symbolName) ?? .list }
}

struct CustomListEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: TaskListRecord.displayOrder) private var lists: [TaskListRecord]
    let list: TaskListRecord?
    @FocusState private var nameFocused: Bool
    @State private var name: String
    @State private var color: ListCardColor
    @State private var icon: ListCardIcon
    @State private var error: String?

    @State private var tags: [TaskTag]
    @State private var originalTagIDs: Set<UUID>
    @State private var addingTag = false
    @State private var tagSessionID = UUID()
    @State private var editingTag: TaskTag?
    @State private var confirmingDelete = false
    let onDelete: () -> Void

    init(list: TaskListRecord? = nil, onDelete: @escaping () -> Void = {}) {
        self.onDelete = onDelete
        self.list = list
        _tags = State(initialValue: list?.tags ?? [])
        _originalTagIDs = State(initialValue: Set(list?.tags.map(\.id) ?? []))
        _name = State(initialValue: list?.name ?? "")
        _color = State(initialValue: list?.cardColor ?? .indigo)
        _icon = State(initialValue: list?.cardIcon ?? .list)
    }

    private var hasChanges: Bool {
        name != (list?.name ?? "") || color != (list?.cardColor ?? .indigo)
            || icon != (list?.cardIcon ?? .list) || tags != (list?.tags ?? [])
    }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var duplicateName: Bool {
        func matches(_ other: String) -> Bool {
            trimmedName.caseInsensitiveCompare(other.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        }
        return TaskList.builtIns.contains { matches($0.title) } ||
            lists.contains { $0.persistentModelID != list?.persistentModelID && matches($0.name) }
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
                    .onSubmit { save() }
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
                ForEach(tags) { tag in
                    Button(tag.name) { editingTag = tag }.foregroundStyle(.primary)
                }
                    .onMove { tags.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { tags.remove(atOffsets: $0) }
                Button("New Tag") {
                    tagSessionID = UUID()
                    addingTag = true
                }.tint(.blue)
            } header: {
                Text("Tags")
            } footer: {
                if !tags.isEmpty { Text("Drag to reorder or swipe to delete. Tasks in a deleted tag stay in this list.") }
            }
            if let list {
                Section {
                    Button("Delete List", role: .destructive) { confirmingDelete = true }
                        .confirmationDialog("Delete this list?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete List", role: .destructive) {
                                do {
                                    try list.deleteKeepingTasks(in: context)
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
        .onAppear { if list == nil { nameFocused = true } }
        .navigationTitle(list == nil ? "New List" : "Edit List")
        .sheet(isPresented: $addingTag) {
            TaskTagEditor(tags: tags) { tags.append($0) }
                .id(tagSessionID)
        }
        .sheet(item: $editingTag) { tag in
            TaskTagEditor(tag: tag, tags: tags) { edited in
                if let index = tags.firstIndex(where: { $0.id == edited.id }) { tags[index] = edited }
            }
        }
        .confirmUnsavedChanges(hasChanges)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(list == nil ? "Create" : "Save") { save() }.disabled(!canSave)
            }
        }
        .alert("Couldn’t Save List", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private func save() {
        guard canSave else { return }
        let list = list ?? TaskListRecord(name: trimmedName, position: (lists.last?.position ?? -1) + 1)
        if self.list == nil { context.insert(list) }
        list.name = trimmedName
        list.colorName = color.rawValue
        list.symbolName = icon.rawValue
        do {
            try list.applyTagEdits(tags, originalIDs: originalTagIDs, in: context)
            try context.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            context.rollback()
            self.error = error.localizedDescription
        }
    }
}
