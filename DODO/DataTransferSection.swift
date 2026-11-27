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

private struct PendingImport {
    let mode: BackupStore.ImportMode
    let backup: DODOBackup
    let modifiedAt: Date?
    let filename: String
}

private nonisolated struct BackupFileContents: Sendable {
    let data: Data
    let modifiedAt: Date?
    let filename: String

    static func read(_ url: URL) throws -> Self {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Self, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { location in
            result = Result {
                let metadata = try location.resourceValues(forKeys: [.contentModificationDateKey])
                return Self(data: try Data(contentsOf: location), modifiedAt: metadata.contentModificationDate,
                            filename: url.lastPathComponent)
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
    @State private var pending: PendingImport?
    @State private var confirmingImport = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        Section {
            Button("Export Data") { export() }.tint(.blue)
            Button("Import & Merge Data") { beginImport(.merge) }.tint(.blue)
            Button("Import & Replace All") { beginImport(.replace) }.tint(.blue)
        } header: {
            Text("Export & Import")
        } footer: {
            if busy { Text("Reading data…") }
            else {
                Text("Export backs up all data and settings. Merge adds imported data and keeps your settings. Replace All replaces all local data and settings.")
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
                    pending = PendingImport(mode: mode, backup: try DODOBackup.decode(file.data), modifiedAt: file.modifiedAt,
                                            filename: file.filename)
                    confirmingImport = true
                } catch { report(error) }
            }
        }
        .confirmationDialog(pending?.mode == .replace ? "Replace All Data and Settings?" : "Merge Imported Data?",
                            isPresented: $confirmingImport, titleVisibility: .visible) {
            if pending?.mode == .replace {
                Button("Replace All", role: .destructive) { apply() }
            } else {
                Button("Import & Merge") { apply() }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            if let pending {
                let modified = pending.modifiedAt?.formatted(date: .numeric, time: .shortened) ?? "Unknown"
                let explanation = pending.mode == .replace
                    ? "All local tasks, lists, tags, and settings will be replaced. This cannot be undone."
                    : "Imported tasks will be added, including duplicates. Matching lists and tags will be reused. Existing data and settings will be kept."
                Text("\(pending.filename)\nModified: \(modified)\nTasks: \(pending.backup.tasks.count.formatted()) (including Recently Deleted)\n\n\(explanation)")
            }
        }
        .alert("Couldn’t Transfer Data", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: { Text(errorMessage ?? "") }
        .alert("Done", isPresented: Binding(get: { successMessage != nil }, set: { if !$0 { successMessage = nil } })) {
            Button("OK") {}
        } message: { Text(successMessage ?? "") }
    }

    private func export() {
        do {
            document = BackupDocument(data: try BackupStore.snapshot(context: context).encoded())
            exporting = true
        } catch { report(error) }
    }

    private func beginImport(_ mode: BackupStore.ImportMode) {
        pending = nil
        importMode = mode
        importing = true
    }

    private func apply() {
        guard let pending else { return }
        busy = true
        defer { busy = false; self.pending = nil }
        do {
            try BackupStore.apply(pending.backup, mode: pending.mode, context: context)
            onImport()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            successMessage = "\(pending.backup.tasks.count.formatted()) tasks imported."
        } catch { report(error) }
    }

    private func report(_ error: Error) {
        guard (error as NSError).code != NSUserCancelledError else { return }
        errorMessage = error.localizedDescription
    }
}
