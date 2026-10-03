import AppKit
import CryptoKit
import Foundation
import Observation

enum InstallState: Equatable {
    case notInstalled
    case downloading(Double)
    case verifying
    case installed
    case failed(String)
}

enum ModelStoreError: LocalizedError {
    case checksumMismatch
    case sizeMismatch
    case denied
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .checksumMismatch: "The downloaded file failed its checksum and was deleted."
        case .sizeMismatch: "The downloaded file has the wrong size and was deleted."
        case .denied: "Access to this model was not granted."
        case .badResponse(let code): "The server answered with status \(code)."
        }
    }
}

/// Decides whether a download may start. T7 installs the Hugging Face implementation.
protocol AccessPolicy: Sendable {
    func authorize(_ entry: ModelEntry) async -> Bool
}

struct AllowAllPolicy: AccessPolicy {
    func authorize(_ entry: ModelEntry) async -> Bool { true }
}

@MainActor @Observable
final class ModelStore {
    private(set) var states: [String: InstallState] = [:]
    var policy: any AccessPolicy = AllowAllPolicy()
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SillyMIDITools/Models", isDirectory: true)
        refresh()
    }

    func state(for entry: ModelEntry) -> InstallState {
        entry.needsDownload ? (states[entry.id] ?? .notInstalled) : .installed
    }

    func installedURL(for entry: ModelEntry) -> URL? {
        guard entry.needsDownload, state(for: entry) == .installed else { return nil }
        return directory.appendingPathComponent(entry.fileName)
    }

    func refresh() {
        for entry in ModelCatalog.entries where entry.needsDownload {
            if case .downloading = states[entry.id] { continue }
            let url = directory.appendingPathComponent(entry.fileName)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            states[entry.id] = size == entry.byteSize ? .installed : .notInstalled
        }
    }

    func install(_ entry: ModelEntry) async {
        guard entry.needsDownload, let remote = entry.downloadURL, let expected = entry.sha256 else { return }
        if case .downloading = state(for: entry) { return }
        guard await policy.authorize(entry) else {
            states[entry.id] = .failed(ModelStoreError.denied.localizedDescription)
            return
        }
        states[entry.id] = .downloading(0)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let progress = ProgressRelay { [weak self] value in
                Task { @MainActor in
                    if case .downloading = self?.states[entry.id] { self?.states[entry.id] = .downloading(value) }
                }
            }
            let (temp, response) = try await URLSession.shared.download(from: remote, delegate: progress)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                try? FileManager.default.removeItem(at: temp)
                throw ModelStoreError.badResponse(http.statusCode)
            }
            states[entry.id] = .verifying
            try await Self.verify(fileAt: temp, sha256: expected, byteSize: entry.byteSize)
            let destination = directory.appendingPathComponent(entry.fileName)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temp, to: destination)
            states[entry.id] = .installed
        } catch {
            states[entry.id] = .failed(error.localizedDescription)
        }
    }

    func delete(_ entry: ModelEntry) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.fileName))
        states[entry.id] = .notInstalled
    }

    func reveal(_ entry: ModelEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([directory.appendingPathComponent(entry.fileName)])
    }

    /// Hashes in 1 MiB chunks off the main actor. A bad file is deleted before the error is thrown.
    nonisolated static func verify(fileAt url: URL, sha256 expected: String, byteSize: Int64) async throws {
        try await Task.detached(priority: .utility) {
            func discard() { try? FileManager.default.removeItem(at: url) }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            guard size == byteSize else { discard(); throw ModelStoreError.sizeMismatch }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest == expected else { discard(); throw ModelStoreError.checksumMismatch }
        }.value
    }
}

private final class ProgressRelay: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [report] progress, _ in
            report(progress.fractionCompleted)
        }
    }
}

/// Anchor class so tests and views can find the app bundle.
final class ModelStoreProbe {}
