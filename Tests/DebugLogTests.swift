import Foundation
import Testing
@testable import SillyMIDITools

/// Each test gets its own log and folder; the app's shared log is never switched on while tests run.
struct DebugLogTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "smt-log-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func logs(_ folder: URL) -> URL {
        folder.appending(path: DebugLog.folderName, directoryHint: .isDirectory)
    }

    private func text(_ url: URL?) throws -> String {
        try String(contentsOf: #require(url), encoding: .utf8)
    }

    /// An old log, its modification date pushed back so it sorts before anything written now.
    private func writeOldLog(_ name: String, _ contents: String, in folder: URL, age: TimeInterval) throws -> URL {
        try FileManager.default.createDirectory(at: logs(folder), withIntermediateDirectories: true)
        let url = logs(folder).appending(path: name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
        return url
    }

    @Test func theAppsOwnLogStaysOffUnderTests() {
        #expect(DebugLog.runsUnderTests)
        #expect(DebugLog.shared.isEnabled == false)
    }

    @Test func writesNothingWhileOff() throws {
        let folder = try folder()
        let log = DebugLog()
        log.configure(enabled: false, folder: folder)
        log.log(.app, "should not appear")
        #expect(log.currentFile == nil)
        #expect(!FileManager.default.fileExists(atPath: logs(folder).path))
    }

    @Test func writesAHeaderThenTimestampedLines() throws {
        let folder = try folder()
        let log = DebugLog()
        log.configure(enabled: true, folder: folder)
        log.log(.transcription, "first line\nsecond line")
        let file = try #require(log.currentFile)
        #expect(file.deletingLastPathComponent().lastPathComponent == DebugLog.folderName)
        #expect(file.pathExtension == "log")
        let text = try text(file)
        #expect(text.hasPrefix("Silly MIDI Tools debug log"))
        #expect(text.contains("App:      "))
        #expect(text.contains("Folder:   \(folder.path)"))
        #expect(text.contains("SillyMIDITools"), "the image list names the app's binary")
        #expect(text.contains(#/\d\d:\d\d:\d\d\.\d{3} \[(main|bg  )\] transcription +first line\n +second line/#))
        #expect(log.problem == nil)
    }

    @Test func linesWaitForAWorkingFolder() throws {
        let folder = try folder()
        let log = DebugLog()
        log.configure(enabled: true, folder: nil)
        log.log(.app, "before the folder")
        #expect(log.currentFile == nil)
        #expect(log.problem != nil)

        log.configure(enabled: true, folder: folder)

        #expect(try text(log.currentFile).contains("before the folder"))
    }

    @Test func turningOffEndsTheFileCleanly() throws {
        let folder = try folder()
        let log = DebugLog()
        log.configure(enabled: true, folder: folder)
        let file = try #require(log.currentFile)

        log.configure(enabled: false, folder: folder)
        log.log(.app, "after turning off")

        #expect(log.currentFile == nil)
        let text = try text(file)
        #expect(text.hasSuffix("\(DebugLog.endLine)\n"))
        #expect(!text.contains("after turning off"))
    }

    @Test func aNewWorkingFolderStartsANewFile() throws {
        let first = try folder()
        let second = try folder()
        let log = DebugLog()
        log.configure(enabled: true, folder: first)
        let firstFile = try #require(log.currentFile)

        log.configure(enabled: true, folder: second)
        log.log(.app, "in the second folder")

        #expect(try text(firstFile).contains(DebugLog.endLine))
        #expect(log.currentFile?.path.hasPrefix(second.path) == true)
        #expect(try text(log.currentFile).contains("in the second folder"))
    }

    @Test func keepsTheNewestTenLogs() throws {
        let folder = try folder()
        for index in 0..<12 {
            _ = try writeOldLog("old \(index).log", "\(DebugLog.endLine)\n", in: folder, age: Double(100 + index))
        }
        let log = DebugLog()
        log.configure(enabled: true, folder: folder)

        let kept = DebugLog.logFiles(in: logs(folder))
        #expect(kept.count == DebugLog.keptFiles)
        // Compared by name: a listing can spell the folder /private/var where the log was opened as /var.
        #expect(kept.first?.lastPathComponent == log.currentFile?.lastPathComponent)
        #expect(!kept.contains { $0.lastPathComponent == "old 11.log" }, "the oldest go first")
        #expect(kept.contains { $0.lastPathComponent == "old 0.log" })
    }

    @Test func saysWhenThePreviousSessionDidNotEndCleanly() throws {
        let folder = try folder()
        _ = try writeOldLog("previous.log", "header\n12:00:00.000 [main] audio         Decoding \"take.wav\"\n", in: folder, age: 60)
        let log = DebugLog()
        log.configure(enabled: true, folder: folder)

        let text = try text(log.currentFile)
        #expect(text.contains("The previous session (previous.log) didn\u{2019}t end cleanly"))
        #expect(text.contains("  | 12:00:00.000 [main] audio         Decoding \"take.wav\""))
    }

    @Test func saysWhenThePreviousSessionCrashed() throws {
        let folder = try folder()
        _ = try writeOldLog("previous.log", "header\n\(CrashCapture.marker): SIGTRAP on the main thread\n", in: folder, age: 60)
        let log = DebugLog()
        log.configure(enabled: true, folder: folder)

        #expect(try text(log.currentFile).contains("The previous session (previous.log) crashed."))
    }

    @Test func theNoteQuotesOnlyThePreviousSessionsOwnLines() throws {
        let folder = try folder()
        let previous = [
            "Silly MIDI Tools debug log", "Folder:   /x", DebugLog.separator,
            "\(DebugLog.previousSessionPrefix)older.log) crashed. Its last lines:", "  | 11:00:00.000 [main] app           older line",
            "12:00:00.000 [main] app           Simulating a crash.",
            "\(CrashCapture.marker): SIGILL (illegal instruction) on the main thread",
            "0   SillyMIDITools.debug.dylib          0x0000000105de25e5 $s14SillyMIDITools18crashSignalHandler + 597",
        ].joined(separator: "\n") + "\n"
        _ = try writeOldLog("previous.log", previous, in: folder, age: 60)
        let log = DebugLog()
        log.configure(enabled: true, folder: folder)

        let text = try text(log.currentFile)
        #expect(text.contains("  | 12:00:00.000 [main] app           Simulating a crash."))
        #expect(text.contains("  | \(CrashCapture.marker): SIGILL"))
        #expect(!text.contains("older line"))
        #expect(!text.contains("older.log"))
        #expect(!text.contains("  | Folder:"))
        #expect(!text.contains("crashSignalHandler"))
    }

    @Test func aCleanSessionThatQuotedAnEarlierCrashIsNotMentioned() throws {
        let folder = try folder()
        let previous = [
            "Silly MIDI Tools debug log", DebugLog.separator,
            "\(DebugLog.previousSessionPrefix)older.log) crashed. Its last lines:",
            "  | \(CrashCapture.marker): SIGSEGV (bad memory access) on the main thread",
            "12:00:00.000 [main] app           The app quit normally. \(DebugLog.endLine)",
        ].joined(separator: "\n") + "\n"
        _ = try writeOldLog("previous.log", previous, in: folder, age: 60)
        let log = DebugLog()
        log.configure(enabled: true, folder: folder)

        #expect(try !text(log.currentFile).contains(DebugLog.previousSessionPrefix))
    }

    @Test func aCleanPreviousSessionIsNotMentioned() throws {
        let folder = try folder()
        _ = try writeOldLog("previous.log", "header\nThe app quit normally. \(DebugLog.endLine)\n", in: folder, age: 60)
        let log = DebugLog()
        log.configure(enabled: true, folder: folder)

        #expect(try !text(log.currentFile).contains("previous session"))
    }

    @Test func tokensNeverReachTheFile() throws {
        let folder = try folder()
        let log = DebugLog()
        log.configure(enabled: true, folder: folder)
        log.log(.access, "saved hf_AbCdEf0123456789 then sent Authorization: Bearer hf_ZyXw98765 and Bearer secret-value")

        let text = try text(log.currentFile)
        #expect(!text.contains("AbCdEf0123456789"))
        #expect(!text.contains("ZyXw98765"))
        #expect(!text.contains("secret-value"))
        #expect(text.contains("hf_[redacted]"))
        #expect(text.contains("Bearer [redacted]"))
    }

    @Test func aSecondLaunchInTheSameSecondGetsItsOwnFile() throws {
        let folder = try folder()
        let fixed = Date(timeIntervalSince1970: 1_800_000_000)
        let first = DebugLog(now: { fixed })
        first.configure(enabled: true, folder: folder)
        let second = DebugLog(now: { fixed })
        second.configure(enabled: true, folder: folder)

        #expect(first.currentFile != second.currentFile)
        #expect(second.currentFile?.lastPathComponent == "\(DebugLog.stamp(fixed)) 2.log")
    }
}
