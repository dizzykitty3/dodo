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
    @State private var pending: PendingImport?
    @State private var confirmingImport = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        Section {
            Button("Export Data") { export() }.tint(.blue)
            Button("Import Data") { importing = true }.tint(.blue)
        } header: {
            Text("Export & Import")
        } footer: {
            if busy { Text("Reading data…") }
            else { Text("Back up all tasks, lists, groups, and settings as a JSON file.") }
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
            Task {
                busy = true
                defer { busy = false }
                do {
                    let url = try result.get()
                    let file = try await Task.detached { try BackupFileContents.read(url) }.value
                    pending = PendingImport(backup: try DODOBackup.decode(file.data), modifiedAt: file.modifiedAt,
                                            filename: file.filename)
                    confirmingImport = true
                } catch { report(error) }
            }
        }
        .confirmationDialog("Import DODO Data?", isPresented: $confirmingImport, titleVisibility: .visible) {
            Button("Replace All Data", role: .destructive) { apply(.replace) }
            Button("Merge Data") { apply(.merge) }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            if let pending {
                let modified = pending.modifiedAt?.formatted(date: .numeric, time: .shortened) ?? "Unknown"
                Text("\(pending.filename)\nModified: \(modified)\nTasks: \(pending.backup.tasks.count.formatted()) (including Recently Deleted)\n\nReplace deletes all local data and replaces settings. Merge adds every imported task, including duplicates, and keeps local settings.")
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

    private func apply(_ mode: BackupStore.ImportMode) {
        guard let pending else { return }
        busy = true
        defer { busy = false; self.pending = nil }
        do {
            try BackupStore.apply(pending.backup, mode: mode, context: context)
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
