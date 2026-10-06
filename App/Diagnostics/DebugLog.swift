import Darwin
import Foundation
import MachO
import Synchronization

/// Shorthand for `DebugLog.shared.log`. The message is only built while logging is on.
func debugLog(_ area: DebugLog.Area, _ message: @autoclosure () -> String) {
    DebugLog.shared.log(area, message())
}

/// The troubleshooting log. While the user has it on (Settings, General), each launch writes one file to `Logs/` in the
/// working folder: a header that describes the app and the Mac, then one timestamped line for each thing the app did.
/// A crash adds its reason and stack (`CrashCapture`), and the next launch says so when the previous one didn't end
/// cleanly. Lines go straight to the file rather than through a queue, so the last ones before a crash are on disk.
final class DebugLog: Sendable {
    enum Area: String, Sendable {
        case app, folder, library, audio, transcription, engine, models, access, playback, midi, export, memory
    }

    static let shared = DebugLog(capturesProcessOutput: true)

    static let folderName = "Logs"
    static let keptFiles = 10
    /// A runaway log stops growing here. A crash block is still added.
    static let maximumBytes = 20_000_000
    /// The last line of a session that ended normally.
    static let endLine = "Session ended."
    /// Lines logged before there is a working folder wait for it, up to this many.
    static let pendingLimit = 500
    /// Ends the header.
    static let separator = String(repeating: "-", count: 100)
    /// Starts the note about the previous session.
    static let previousSessionPrefix = "The previous session ("

    /// The app is also the host of the unit tests; the app's own log is never switched on there.
    static let runsUnderTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    private struct State {
        var enabled = false
        var folder: URL?
        var file: URL?
        var problem: String?
        var descriptor: Int32 = -1
        var written = 0
        var full = false
        var pending: [String] = []
        var savedStandardError: Int32 = -1
        var pressure: [any DispatchSourceMemoryPressure] = []
    }

    private let state = Mutex(State())
    private let on = Atomic(false)
    /// The app's own log also takes over stderr, catches crashes and watches memory pressure. A test's log does none.
    private let capturesProcessOutput: Bool
    private let now: @Sendable () -> Date

    init(capturesProcessOutput: Bool = false, now: @escaping @Sendable () -> Date = { Date() }) {
        self.capturesProcessOutput = capturesProcessOutput
        self.now = now
    }

    var isEnabled: Bool { on.load(ordering: .relaxed) }

    /// The file being written, if any.
    var currentFile: URL? { state.withLock { $0.file } }

    /// Why logging is on but nothing is being written, in words for Settings.
    var problem: String? { state.withLock { $0.problem } }

    func log(_ area: Area, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = format(area, Self.redacted(message()))
        state.withLock { state in
            guard state.enabled else { return }
            if state.descriptor >= 0 {
                append(line, to: &state)
            } else if state.pending.count < Self.pendingLimit {
                state.pending.append(line)
            }
        }
    }

    /// Turns logging on or off and points it at a working folder. Called at launch and whenever either changes;
    /// calling it again with the same values does nothing.
    func configure(enabled: Bool, folder: URL?) {
        if capturesProcessOutput && Self.runsUnderTests { return }
        state.withLock { state in
            let moved = folder?.standardizedFileURL != state.folder?.standardizedFileURL
            switch (state.enabled, enabled) {
            case (false, false):
                state.folder = folder
            case (true, false):
                close(&state, reason: "Debug logging was turned off.")
                state.enabled = false
                state.pending = []
                state.problem = nil
                state.folder = folder
                on.store(false, ordering: .relaxed)
            case (false, true):
                state.enabled = true
                state.folder = folder
                on.store(true, ordering: .relaxed)
                open(&state)
            case (true, true):
                guard moved || state.descriptor < 0 else { return }
                if moved {
                    close(&state, reason: "The working folder changed to \(folder?.path ?? "none"); the log goes on there.")
                    state.folder = folder
                }
                open(&state)
            }
        }
    }

    /// Writes the end line and closes the file, for a normal quit.
    func end() {
        state.withLock { close(&$0, reason: "The app quit normally.") }
    }

    // MARK: Files

    private func open(_ state: inout State) {
        state.problem = nil
        guard let folder = state.folder else {
            state.problem = "Choose a working folder; the log starts there."
            return
        }
        let logs = folder.appending(path: Self.folderName, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        } catch {
            state.problem = "The Logs folder couldn\u{2019}t be created: \(error.localizedDescription)"
            return
        }
        let previous = Self.logFiles(in: logs).first
        let url = Self.newFileURL(in: logs, date: now())
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            state.problem = "The log file couldn\u{2019}t be created: \(String(cString: strerror(errno)))"
            return
        }
        state.descriptor = descriptor
        state.file = url
        state.written = 0
        state.full = false
        append(header(folder: folder), to: &state)
        if let previous, let note = Self.previousSessionNote(previous) { append(note, to: &state) }
        state.pending.forEach { append($0, to: &state) }
        state.pending = []
        Self.prune(logs)
        guard capturesProcessOutput else { return }
        state.savedStandardError = dup(STDERR_FILENO)
        dup2(descriptor, STDERR_FILENO)
        CrashCapture.install(descriptor: descriptor)
        let levels: [DispatchSource.MemoryPressureEvent] = [.warning, .critical]
        state.pressure = levels.map { level in
            let source = DispatchSource.makeMemoryPressureSource(eventMask: level, queue: .global(qos: .utility))
            let name = level == .critical ? "critical" : "warning"
            source.setEventHandler { [weak self] in
                self?.log(.memory, "Memory pressure \(name). The app uses \(DebugLog.footprint()).")
            }
            source.resume()
            return source
        }
    }

    private func close(_ state: inout State, reason: String) {
        guard state.descriptor >= 0 else { return }
        append(format(.app, "\(reason) \(Self.endLine)"), to: &state, always: true)
        if capturesProcessOutput {
            state.pressure.forEach { $0.cancel() }
            state.pressure = []
            CrashCapture.uninstall()
            if state.savedStandardError >= 0 {
                dup2(state.savedStandardError, STDERR_FILENO)
                Darwin.close(state.savedStandardError)
                state.savedStandardError = -1
            }
        }
        Darwin.close(state.descriptor)
        state.descriptor = -1
        state.file = nil
    }

    private func append(_ text: String, to state: inout State, always: Bool = false) {
        if state.full && !always { return }
        var bytes = Array(text.utf8)
        if !always, state.written + bytes.count > Self.maximumBytes {
            state.full = true
            bytes = Array(format(.app, "The log reached \(Self.maximumBytes / 1_000_000) MB; nothing more is written to it this session.").utf8)
        }
        Self.write(bytes, to: state.descriptor)
        state.written += bytes.count
    }

    private static func write(_ bytes: [UInt8], to descriptor: Int32) {
        bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, base + offset, buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return }
                offset += count
            }
        }
    }

    /// The `.log` files in `folder`, newest first.
    static func logFiles(in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return files.filter { $0.pathExtension == "log" }
            .map { ($0, modified($0)) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.lastPathComponent > $1.0.lastPathComponent }
            .map(\.0)
    }

    /// Keeps the newest `keptFiles` logs and the newest `keptFiles` saved system diagnostics.
    private static func prune(_ folder: URL) {
        for file in logFiles(in: folder).dropFirst(keptFiles) { try? FileManager.default.removeItem(at: file) }
        let saved = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for file in saved.dropFirst(keptFiles) { try? FileManager.default.removeItem(at: file) }
    }

    /// `2026-10-06 14.30.12.log`, with ` 2` and so on when a launch in the same second already took the name.
    private static func newFileURL(in folder: URL, date: Date) -> URL {
        let base = stamp(date)
        var url = folder.appending(path: "\(base).log", directoryHint: .notDirectory)
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: "\(base) \(number).log", directoryHint: .notDirectory)
            number += 1
        }
        return url
    }

    /// Writes a file next to the logs, for a diagnostic report macOS hands over. Returns where it went.
    func saveAttachment(_ data: Data, named name: String) -> URL? {
        let folder = state.withLock { $0.descriptor >= 0 ? $0.file?.deletingLastPathComponent() : nil }
        guard let folder else { return nil }
        let url = folder.appending(path: "\(Self.stamp(now())) \(name)", directoryHint: .notDirectory)
        return (try? data.write(to: url)) == nil ? nil : url
    }

    /// What the new log says about the previous one: nothing when it ended normally, otherwise that it didn't and
    /// its last lines.
    static func previousSessionNote(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 64_000 ? size - 64_000 : 0)
        let tail = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        // The session's own lines: not its header, and not its note about the session before it, which can quote a crash.
        var lines = tail.split(separator: "\n")
        if let header = lines.lastIndex(where: { $0 == separator }) { lines = Array(lines[(header + 1)...]) }
        let quote = "  | "
        lines = lines.filter { !$0.hasPrefix(quote) && !$0.hasPrefix(previousSessionPrefix) }
        let crashed = lines.contains { $0.hasPrefix(CrashCapture.marker) }
        guard crashed || !lines.contains(where: { $0.hasSuffix(endLine) }) else { return nil }
        var note = crashed
            ? "\(previousSessionPrefix)\(url.lastPathComponent)) crashed. Its last lines:\n"
            : "\(previousSessionPrefix)\(url.lastPathComponent)) didn\u{2019}t end cleanly: it crashed or was force-quit. Its last lines:\n"
        // Stack frames stay in that file.
        let frame = #/\s*\d+\s+\S.*\s0x[0-9a-f]{8,}\s.*/#
        note += lines.filter { $0.wholeMatch(of: frame) == nil }.suffix(20).map { "\(quote)\($0)\n" }.joined()
        return note
    }

    // MARK: Formatting

    private func format(_ area: Area, _ message: String) -> String {
        let thread = pthread_main_np() != 0 ? "main" : "bg  "
        let indent = "\n" + String(repeating: " ", count: 34)
        let text = message.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: indent)
        return "\(Self.clock(now())) [\(thread)] \(area.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0)) \(text)\n"
    }

    /// Hugging Face tokens and authorisation headers never reach the file, whatever a caller passes.
    static func redacted(_ text: String) -> String {
        guard text.contains("hf_") || text.contains("Bearer ") else { return text }
        return text.replacing(#/hf_[A-Za-z0-9]{4,}/#, with: "hf_[redacted]").replacing(#/Bearer \S+/#, with: "Bearer [redacted]")
    }

    private static func parts(_ date: Date) -> tm {
        var seconds = time_t(date.timeIntervalSince1970.rounded(.down))
        var parts = tm()
        localtime_r(&seconds, &parts)
        return parts
    }

    /// `14:30:12.345`
    static func clock(_ date: Date) -> String {
        let p = parts(date)
        let millis = Int((date.timeIntervalSince1970 - date.timeIntervalSince1970.rounded(.down)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", p.tm_hour, p.tm_min, p.tm_sec, millis)
    }

    /// `2026-10-06 14.30.12`
    static func stamp(_ date: Date) -> String {
        let p = parts(date)
        return String(format: "%04d-%02d-%02d %02d.%02d.%02d", p.tm_year + 1900, p.tm_mon + 1, p.tm_mday, p.tm_hour, p.tm_min, p.tm_sec)
    }

    // MARK: The Mac and the app

    private func header(folder: URL) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let process = ProcessInfo.processInfo
        #if DEBUG
        let configuration = "Debug build"
        #else
        let configuration = "Release build"
        #endif
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        let rosetta = Self.sysctlInt("sysctl.proc_translated") == 1 ? " \u{00B7} running under Rosetta" : ""
        let model = Self.sysctlString("hw.model") ?? "unknown Mac"
        let chip = Self.sysctlString("machdep.cpu.brand_string") ?? "unknown chip"
        let thermal = switch process.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
        var lines = [
            "Silly MIDI Tools debug log",
            "Started:  \(now().formatted(date: .complete, time: .standard))",
            "App:      \(info["CFBundleShortVersionString"] as? String ?? "?") (build \(info["CFBundleVersion"] as? String ?? "?")) \u{00B7} \(configuration) \u{00B7} \(arch)",
            "Bundle:   \(Bundle.main.bundlePath)",
            "macOS:    \(process.operatingSystemVersionString)",
            "Mac:      \(model) \u{00B7} \(chip) \u{00B7} \(process.activeProcessorCount) cores \u{00B7} \(process.physicalMemory / 1_073_741_824) GB memory\(rosetta)",
            "State:    thermal \(thermal) \u{00B7} Low Power Mode \(process.isLowPowerModeEnabled ? "on" : "off") \u{00B7} pid \(process.processIdentifier) \u{00B7} uses \(Self.footprint())",
            "Folder:   \(folder.path)",
            "Images (to symbolicate a crash: atos -o <dSYM> -arch \(arch) -l <load address> <address>):",
        ]
        lines += Self.images().map { "  \($0)" }
        lines.append("Lines read \u{201C}time [thread] area message\u{201D}. Lines without a time are the app\u{2019}s own error output.")
        lines.append(Self.separator)
        return lines.joined(separator: "\n") + "\n"
    }

    /// The app's own binaries as loaded, with their load addresses and UUIDs, so stack addresses can be matched to a dSYM.
    static func images() -> [String] {
        let bundle = Bundle.main.bundlePath
        return (0..<_dyld_image_count()).compactMap { index in
            guard let name = _dyld_get_image_name(index).map({ String(cString: $0) }), name.hasPrefix(bundle),
                  let header = _dyld_get_image_header(index) else { return nil }
            let address = String(format: "0x%lx", UInt(bitPattern: header))
            return "\(URL(fileURLWithPath: name).lastPathComponent)  \(address)  \(uuid(of: header) ?? "no UUID")"
        }
    }

    private static func uuid(of header: UnsafePointer<mach_header>) -> String? {
        var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<header.pointee.ncmds {
            let load = command.loadUnaligned(as: load_command.self)
            if load.cmd == UInt32(LC_UUID) {
                return UUID(uuid: command.loadUnaligned(as: uuid_command.self).uuid).uuidString
            }
            command = command.advanced(by: Int(load.cmdsize))
        }
        return nil
    }

    /// The memory the app is charged for, as Activity Monitor shows it: `312 MB`.
    static func footprint() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? "\(info.phys_footprint / 1_000_000) MB" : "an unknown amount of memory"
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static func sysctlInt(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }
}
