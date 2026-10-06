import Darwin
import Foundation

/// Adds a crash block to the debug log: the signal and the stack. Then the crash goes on to macOS as before, so its own
/// report in `~/Library/Logs/DiagnosticReports` is still written. What comes just before the block is the runtime's own
/// account, written to stderr and so to the log: Swift's `Fatal error: …` line, or an uncaught exception's name, reason
/// and first-throw stack.
///
/// The signal handler runs inside a crashed process, so it only calls what is safe there (`write`, `backtrace`,
/// `backtrace_symbols_fd`, `sigaction`, `raise`) and only touches memory set up by `install`.
enum CrashCapture {
    /// Starts every crash block, so the next launch can tell that the previous one crashed.
    static let marker = "*** CRASH"

    /// Faults re-run their instruction after the handler returns and crash again under the restored handler, which keeps
    /// the original crash for macOS. Signals that were sent (`abort()`, `kill`, a broken pipe) are raised again instead.
    fileprivate static let signals: [Int32] = [SIGABRT, SIGILL, SIGTRAP, SIGSEGV, SIGBUS, SIGFPE, SIGPIPE]

    /// Points the handlers at the log file, installing them the first time.
    static func install(descriptor: Int32) {
        crashDescriptor = descriptor
        guard !installed else { return }
        if frames == nil {
            frames = .allocate(capacity: Int(frameCapacity))
            // The first call can load the unwinder; that must not happen inside a crash.
            _ = backtrace(frames!, frameCapacity)
        }
        if savedActions == nil {
            savedActions = .allocate(capacity: Int(NSIG))
            savedActions?.initialize(repeating: sigaction(), count: Int(NSIG))
        }
        if alternateStack == nil {
            // A stack overflow leaves no stack to run the handler on, so one is set aside. `sigaltstack` covers only the
            // calling thread, the main thread; an overflow elsewhere still crashes, just without a block in the log.
            let size = 128 * 1024
            alternateStack = .allocate(byteCount: size, alignment: 16)
            var stack = stack_t(ss_sp: alternateStack, ss_size: size, ss_flags: 0)
            sigaltstack(&stack, nil)
        }
        handledCount = 0
        for signal in signals {
            // A signal someone set to be ignored stays ignored; it isn't a crash.
            var current = sigaction()
            sigaction(signal, nil, &current)
            if unsafeBitCast(current.__sigaction_u.__sa_handler, to: Int.self) == 1 { continue }
            var action = sigaction()
            action.__sigaction_u.__sa_sigaction = crashSignalHandler
            action.sa_flags = SA_ONSTACK | SA_SIGINFO
            action.sa_mask = 0
            sigaction(signal, &action, savedActions! + Int(signal))
            handled[handledCount] = signal
            handledCount += 1
        }
        installed = true
    }

    /// Gives the signals back to whoever had them before.
    static func uninstall() {
        crashDescriptor = -1
        guard installed, let savedActions else { return }
        for index in 0..<handledCount { sigaction(handled[index], savedActions + Int(handled[index]), nil) }
        installed = false
    }
}

private let frameCapacity: Int32 = 128
private nonisolated(unsafe) var crashDescriptor: Int32 = -1
private nonisolated(unsafe) var installed = false
private nonisolated(unsafe) var savedActions: UnsafeMutablePointer<sigaction>?
private nonisolated(unsafe) var frames: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
private nonisolated(unsafe) var alternateStack: UnsafeMutableRawPointer?
private nonisolated(unsafe) var handled = [Int32](repeating: 0, count: 16)
private nonisolated(unsafe) var handledCount = 0

private func put(_ descriptor: Int32, _ text: StaticString) {
    _ = write(descriptor, text.utf8Start, text.utf8CodeUnitCount)
}

private func name(of signal: Int32) -> StaticString {
    switch signal {
    case SIGABRT: "SIGABRT (abort: a failed check, an uncaught exception or a fatal error)"
    case SIGILL: "SIGILL (illegal instruction: on Intel, a Swift runtime check such as an index out of range)"
    case SIGTRAP: "SIGTRAP (trap: on Apple silicon, a Swift runtime check such as an index out of range)"
    case SIGSEGV: "SIGSEGV (bad memory access)"
    case SIGBUS: "SIGBUS (bad memory access)"
    case SIGFPE: "SIGFPE (arithmetic error)"
    case SIGPIPE: "SIGPIPE (wrote to a pipe or socket that was closed)"
    default: "an unexpected signal"
    }
}

private func crashSignalHandler(_ signal: Int32, _ info: UnsafeMutablePointer<__siginfo>?, _ context: UnsafeMutableRawPointer?) {
    let descriptor = crashDescriptor
    if descriptor >= 0 {
        put(descriptor, "\n*** CRASH: ")  // CrashCapture.marker
        put(descriptor, name(of: signal))
        put(descriptor, pthread_main_np() != 0 ? " on the main thread\n" : " on a background thread\n")
        put(descriptor, "Stack (addresses map to names with the dSYM and the load addresses at the top of this file):\n")
        if let frames {
            backtrace_symbols_fd(frames, backtrace(frames, frameCapacity), descriptor)
        }
        put(descriptor, "*** End of crash. macOS writes its own report to ~/Library/Logs/DiagnosticReports.\n")
    }
    if let savedActions { sigaction(signal, savedActions + Int(signal), nil) }
    // Fault codes are small positive numbers; a sent signal has 0 or SI_USER and up, and wouldn't happen again.
    let code = info?.pointee.si_code ?? 0
    let isFault = signal != SIGABRT && signal != SIGPIPE && code > 0 && code < SI_USER
    if !isFault { raise(signal) }
}
