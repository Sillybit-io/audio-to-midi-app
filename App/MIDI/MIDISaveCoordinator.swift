import AppKit
import Foundation
import Observation

enum UnsavedChoice {
    case save, dontSave, cancel
}

enum MIDISaveError: LocalizedError, Equatable {
    case noNotes
    case changedOnDisk(String)
    case cannotWrite(file: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .noNotes: "A MIDI file needs at least one note. Undo the deletions, or choose Don\u{2019}t Save."
        case .changedOnDisk(let file): "\u{201C}\(file)\u{201D} changed on disk after you opened it, so it wasn\u{2019}t overwritten."
        case .cannotWrite(let file, let reason): "Couldn\u{2019}t save \u{201C}\(file)\u{201D}. \(reason)"
        }
    }
}

/// Size and modification date, to notice that a file was replaced behind the editor's back.
struct FileFingerprint: Equatable, Sendable {
    var size: Int
    var modified: Date

    /// Read from the file system each time: `URL.resourceValues` caches per URL and would hide a change.
    static func of(_ url: URL) -> FileFingerprint? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue, let modified = attributes[.modificationDate] as? Date else { return nil }
        return FileFingerprint(size: size, modified: modified)
    }
}

enum AtomicFile {
    /// Writes beside `destination` first, then swaps the finished file in, so a failure leaves the old file exactly as it was.
    static func replace(_ data: Data, at destination: URL, fileManager: FileManager = .default) throws {
        let staging = destination.deletingLastPathComponent().appending(path: ".save-\(UUID().uuidString).tmp", directoryHint: .notDirectory)
        do {
            try data.write(to: staging)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
            } else {
                try fileManager.moveItem(at: staging, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }
}

/// Saves the open MIDI file and guards every way of leaving it. Switching files, closing the window and quitting all go
/// through `confirmLeaving`, so there is one Save / Don't Save / Cancel state machine and one place that writes.
@MainActor @Observable
final class MIDISaveCoordinator {
    /// The file being edited, if any. The editor view sets this when it opens and clears it when it closes.
    var editor: MIDIEditorModel?
    private(set) var saveFailure: (name: String, message: String)?
    private(set) var promptIsOpen = false

    @ObservationIgnored var presenter: @MainActor (_ name: String, _ completion: @escaping (UnsavedChoice) -> Void) -> Void = MIDISaveCoordinator.presentAlert
    @ObservationIgnored var onSaved: () -> Void = {}
    @ObservationIgnored private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var hasUnsavedChanges: Bool { editor?.document.isDirty ?? false }

    func dismissFailure() {
        saveFailure = nil
    }

    /// Keeps a window's close-button dot in step with the document.
    func sync(window: NSWindow) {
        let edited = hasUnsavedChanges
        if window.isDocumentEdited != edited { window.isDocumentEdited = edited }
    }

    @discardableResult
    func saveOpenFile() -> Bool {
        guard let editor else { return false }
        return save(editor)
    }

    /// Writes the document to its own file with `edited=1`. The document stays dirty unless the write succeeds.
    @discardableResult
    func save(_ editor: MIDIEditorModel) -> Bool {
        let document = editor.document
        let file = editor.url.lastPathComponent
        do {
            guard !document.notes.isEmpty else { throw MIDISaveError.noNotes }
            if let known = editor.fingerprint, FileFingerprint.of(editor.url) != known { throw MIDISaveError.changedOnDisk(file) }

            var provenance = editor.provenance ?? MIDIProvenance()
            provenance.edited = true
            var options = MIDIExportOptions()
            options.title = editor.name
            options.provenance = provenance
            options.copyright = provenance.modelID.flatMap { id in ModelCatalog.entries.first { $0.id == id } }?.exportNotice
            let data = try MIDIBuilder.build(notes: document.noteEvents, options: options)
            do {
                try AtomicFile.replace(data, at: editor.url, fileManager: fileManager)
            } catch {
                throw MIDISaveError.cannotWrite(file: file, reason: TranscriptionWriter.reason(for: error))
            }
            editor.provenance = provenance
            editor.fingerprint = FileFingerprint.of(editor.url)
            document.markSaved()
            saveFailure = nil
            onSaved()
            return true
        } catch {
            saveFailure = (file, error.localizedDescription)
            return false
        }
    }

    /// Runs `proceed` when it is safe to leave the open file: at once when nothing is unsaved, after a successful Save,
    /// or after Don't Save. Cancel, or a Save that fails, runs `cancelled` and leaves the file and its edits as they were.
    func confirmLeaving(then proceed: @escaping () -> Void, cancelled: @escaping () -> Void = {}) {
        guard let editor, editor.document.isDirty else {
            proceed()
            return
        }
        guard !promptIsOpen else {
            cancelled()
            return
        }
        promptIsOpen = true
        presenter(editor.name) { [weak self] choice in
            guard let self else { return }
            promptIsOpen = false
            switch choice {
            case .save:
                if save(editor) { proceed() } else { cancelled() }
            case .dontSave:
                proceed()
            case .cancel:
                cancelled()
            }
        }
    }

    /// The standard alert, as a sheet on the main window.
    static func presentAlert(name: String, completion: @escaping (UnsavedChoice) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to \u{201C}\(name)\u{201D}?"
        alert.informativeText = "Your changes will be lost if you don\u{2019}t save them."
        alert.addButton(withTitle: "Save")
        let discard = alert.addButton(withTitle: "Don\u{2019}t Save")
        discard.keyEquivalent = "d"
        discard.keyEquivalentModifierMask = .command
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        let respond: (NSApplication.ModalResponse) -> Void = { response in
            switch response {
            case .alertFirstButtonReturn: completion(.save)
            case .alertSecondButtonReturn: completion(.dontSave)
            default: completion(.cancel)
            }
        }
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) ?? NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: respond)
        } else {
            respond(alert.runModal())
        }
    }
}
