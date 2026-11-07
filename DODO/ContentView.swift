import SwiftUI

private enum TaskList: String, CaseIterable, Identifiable {
    case today = "Today", urgent = "Urgent", completed = "Completed"
    case scheduled = "Scheduled", personal = "Personal"

    var id: Self { self }
    var color: Color {
        switch self {
        case .today: Color(red: 0.12, green: 0.38, blue: 0.66)
        case .urgent: Color(red: 0.64, green: 0.22, blue: 0.33)
        case .completed: Color(red: 0.28, green: 0.38, blue: 0.38)
        case .scheduled: Color(red: 0.53, green: 0.32, blue: 0.16)
        case .personal: Color(red: 0.42, green: 0.31, blue: 0.61)
        }
    }
    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .urgent: "flag.fill"
        case .completed: "checkmark"
        case .scheduled: "calendar"
        case .personal: "person.fill"
        }
    }
}

private struct DemoTask: Identifiable {
    let id = UUID()
    let title: String
    var lists: Set<TaskList>
}

private enum Panel: Identifiable, Hashable {
    case search, settings, compose
    var id: Self { self }
}

struct ContentView: View {
    @State private var tasks = [
        DemoTask(title: "Pick up the film prints", lists: [.today, .personal]),
        DemoTask(title: "Review the weekend itinerary", lists: [.today, .urgent, .scheduled]),
        DemoTask(title: "Water the balcony plants", lists: [.today, .personal]),
        DemoTask(title: "Return the library books", lists: [.today, .scheduled]),
        DemoTask(title: "Book a table for Friday", lists: [.scheduled, .personal]),
        DemoTask(title: "Send the photos to Alex", lists: [.completed])
    ]
    @State private var panel: Panel?
    @State private var query = ""
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    card(.today)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        ForEach(TaskList.allCases.filter { $0 != .today }) { card($0) }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("DODO")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Search", systemImage: "magnifyingglass") {
                        query = ""
                        panel = .search
                    }
                    .labelStyle(.iconOnly)
                    Button("Settings", systemImage: "gearshape") { panel = .settings }
                        .labelStyle(.iconOnly)
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button("New Task", systemImage: "square.and.pencil") {
                        draft = ""
                        panel = .compose
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .navigationDestination(for: TaskList.self) { list in
                List(items(list)) { Text($0.title) }
                    .navigationTitle(list.rawValue)
                    .toolbar(.visible, for: .navigationBar)
            }
        }
        .sheet(item: $panel) { selected in
            NavigationStack {
                Group {
                    switch selected {
                    case .search:
                        let matches = tasks.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
                        List(matches) { Text($0.title) }
                            .overlay {
                                if matches.isEmpty { ContentUnavailableView.search(text: query) }
                            }
                            .navigationTitle("Search")
                            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search tasks")
                    case .settings:
                        Color.clear.navigationTitle("Settings")
                    case .compose:
                        Form {
                            TextField("Task title", text: $draft)
                                .onSubmit { addTask() }
                        }
                        .navigationTitle("New Task")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") { addTask() }
                                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { panel = nil }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }

    private func items(_ list: TaskList) -> [DemoTask] {
        tasks.filter { $0.lists.contains(list) }
    }

    private func addTask() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        tasks.insert(DemoTask(title: title, lists: [.today]), at: 0)
        panel = nil
    }

    private func card(_ list: TaskList) -> some View {
        let entries = items(list)
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return NavigationLink(value: list) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    Image(systemName: list.symbol).font(.title3.weight(.semibold))
                    if list == .today { Text("Today").font(.title2.bold()) }
                    Spacer(minLength: 2)
                    Text("\(entries.count)").font(.title.bold()).monospacedDigit()
                }
                if list == .today {
                    ForEach(entries.prefix(3)) { task in
                        Divider().overlay(.white.opacity(0.25))
                        HStack(spacing: 10) {
                            Image(systemName: "circle").foregroundStyle(.white.opacity(0.7))
                            Text(task.title).font(.body)
                        }
                    }
                } else {
                    Text(list.rawValue).font(.headline)
                }
            }
            .foregroundStyle(.white)
            .padding(list == .today ? 20 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(list.color.gradient, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: shape)
    }
}

#Preview { ContentView() }
