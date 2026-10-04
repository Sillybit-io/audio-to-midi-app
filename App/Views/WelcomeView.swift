import SwiftUI

extension URL {
    /// A path inside the account's home folder written as `~/Documents/x`; the sandbox hides the real home from `abbreviatingWithTildeInPath`.
    var abbreviatedPath: String {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

struct WelcomeView: View {
    let workingFolder: WorkingFolderStore
    let onFinish: () -> Void

    @State private var picking = false

    var body: some View {
        VStack(spacing: Metric.sp5) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: Metric.appIcon, height: Metric.appIcon)
                .accessibilityHidden(true)
            Text("Welcome to Silly MIDI Tools").font(.title).bold()
            Text("Turn recordings into MIDI, right on your Mac.").foregroundStyle(Native.fgSecondary)
            VStack(alignment: .leading, spacing: Metric.sp5) {
                step("waveform", "Drop audio, pick a slice", "Drag the handles to transcribe only the part you need.")
                step("cpu", "Choose a model", "MuScriptor for bands and drums, the piano model for piano, Basic Pitch for quick results.")
                step("pencil", "Fix and export", "Tidy notes in the MIDI editor, then export a Type 1 MIDI file.")
            }
            .padding(.vertical, Metric.sp4)
            HStack(spacing: Metric.sp4) {
                Image(systemName: "folder").foregroundStyle(Token.accentText)
                VStack(alignment: .leading, spacing: Metric.sp1) {
                    Text("Your files will be saved in").font(.caption).foregroundStyle(Native.fgSecondary)
                    Text(((workingFolder.folder ?? WorkingFolderStore.suggestedFolder).abbreviatedPath) + "/")
                        .font(.body.monospaced()).textSelection(.enabled)
                }
                Spacer()
                Button("Change…") { picking = true }
            }
            .padding(Metric.sp4)
            .background(Token.surfaceSunken, in: RoundedRectangle(cornerRadius: Metric.rRow))
            if let message = workingFolder.errorMessage {
                Text(message).font(.caption).foregroundStyle(Token.warn).frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Continue") {
                if workingFolder.isResolved { onFinish() } else { picking = true }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent).controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding(Metric.sp8)
        .frame(width: Metric.sheetW + Metric.sp9)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if workingFolder.handlePick(result) { onFinish() }
        }
        .fileDialogDefaultDirectory(WorkingFolderStore.suggestedFolder.deletingLastPathComponent())
        .fileDialogMessage("Choose or create the folder where Silly MIDI Tools keeps your audio and MIDI files.")
        .fileDialogConfirmationLabel("Choose")
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Metric.sp5) {
            Image(systemName: symbol).foregroundStyle(Token.accentText).frame(width: Metric.icon + Metric.sp3)
            VStack(alignment: .leading, spacing: Metric.sp1) {
                Text(title).bold()
                Text(detail).font(.caption).foregroundStyle(Native.fgSecondary)
            }
        }
    }
}
