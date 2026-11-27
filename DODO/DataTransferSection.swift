import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupError.invalid("The selected file could not be read.")
        }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private nonisolated struct BackupFileContents: Sendable {
    let data: Data

    static func read(_ url: URL) throws -> Self {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Self, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { location in
            result = Result {
                Self(data: try Data(contentsOf: location))
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw BackupError.invalid("The selected file could not be read.") }
        return try result.get()
    }
}

struct DataTransferSection: View {
    @Environment(\.modelContext) private var context
    let onImport: () -> Void
    @State private var document: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var importMode = BackupStore.ImportMode.merge
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var imported = false
    @State private var showingSnapshots = false

    var body: some View {
        Section {
            Button("Export Data") { export() }.tint(.blue)
            Button("Import & Merge Data") { beginImport(.merge) }.tint(.blue)
            Button("Import & Replace All") { beginImport(.replace) }.tint(.blue)
            NavigationLink("Import Snapshots") { ImportSnapshotsView(onRestore: onImport) }
        } header: {
            Text("Export & Import")
        } footer: {
            if busy { Text("Importing data…") }
            else {
                Text("Export backs up all data and settings. Merge adds imported data and keeps your settings. Replace All replaces all local data and settings. Selecting a file starts the import automatically after saving a snapshot.")
            }
        }
        .disabled(busy)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "DODO-\(Date.now.formatted(TaskRecord.dayFormat))") { result in
            switch result {
            case .success: successMessage = "Data exported."
            case .failure(let error): report(error)
            }
            document = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            let mode = importMode
            Task {
                busy = true
                defer { busy = false }
                do {
                    let url = try result.get()
                    let file = try await Task.detached { try BackupFileContents.read(url) }.value
                    let backup = try DODOBackup.decode(file.data)
                    try apply(backup, mode: mode)
                } catch { report(error) }
            }
        }
        .alert("Couldn’t Transfer Data", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: { Text(errorMessage ?? "") }
        .sheet(isPresented: $showingSnapshots) {
            NavigationStack {
                ImportSnapshotsView(onRestore: onImport)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") { showingSnapshots = false }
                        }
                    }
            }
            .presentationDetents([.large])
        }
        .alert("Done", isPresented: Binding(get: { successMessage != nil }, set: { if !$0 { successMessage = nil } })) {
            if imported {
                Button("View Snapshots") { showingSnapshots = true }
            }
            Button("OK") {}
        } message: { Text(successMessage ?? "") }
    }

    private func export() {
        imported = false
        do {
            document = BackupDocument(data: try BackupStore.snapshot(context: context).encoded())
            exporting = true
        } catch { report(error) }
    }

    private func beginImport(_ mode: BackupStore.ImportMode) {
        importMode = mode
        importing = true
    }

    private func apply(_ backup: DODOBackup, mode: BackupStore.ImportMode) throws {
        try ImportSnapshots().importData(backup, mode: mode, context: context)
        onImport()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        imported = true
        successMessage = "\(backup.tasks.count.formatted()) tasks imported. Restore an import snapshot to undo this import."
    }

    private func report(_ error: Error) {
        guard (error as NSError).code != NSUserCancelledError else { return }
        errorMessage = error.localizedDescription
    }
}
