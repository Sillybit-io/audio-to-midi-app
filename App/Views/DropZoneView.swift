import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let onOpen: (URL) -> Void
    let onChooseFile: () -> Void
    let folderPath: String?
    @State private var targeted = false

    var body: some View {
        VStack(spacing: Metric.sp6) {
            Image(systemName: "waveform.badge.plus").font(.system(size: Metric.dropSymbol)).accessibilityHidden(true)
            Text("Drop an Audio File").font(.title2.bold())
            Text("Turn a recording into MIDI: pick a model, watch notes appear on the piano roll, play them back next to the original, and export a Standard MIDI File. WAV, MP3, FLAC, M4A, AIFF and other Core Audio formats work. OGG isn\u{2019}t supported.")
                .multilineTextAlignment(.center).foregroundStyle(Native.fgSecondary)
                .frame(maxWidth: Metric.sheetW + Metric.sp10)
            HStack(spacing: Metric.sp4) {
                Button("Choose File…", action: onChooseFile).controlSize(.large)
                Text("⌘O").font(.body.monospaced()).foregroundStyle(Native.muted)
            }
            HStack(alignment: .top, spacing: Metric.sp5) {
                step("01", "Open audio", "Drop a file here or press ⌘O. Drag the handles to transcribe only a slice.")
                step("02", "Pick a model", "MuScriptor for many instruments and drums, the piano model for piano, Basic Pitch for quick pitched audio.")
                step("03", "Play & export", "Mix the original and the notes, change speed, then save a Type 1 .mid.")
            }
            .frame(maxWidth: Metric.sheetW + Metric.sp10 * 2)
            if let folderPath {
                Label("Files are saved in \(folderPath)", systemImage: "folder")
                    .font(.caption).foregroundStyle(Native.fgSecondary)
            }
        }
        .padding(Metric.sp9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(targeted ? Token.accentSoft : .clear)
        .overlay {
            RoundedRectangle(cornerRadius: Metric.rSheet)
                .strokeBorder(style: StrokeStyle(lineWidth: Metric.sp1, dash: [Metric.sp4]))
                .foregroundStyle(targeted ? Token.accent : Native.border)
                .padding(Metric.sp8)
        }
        .dropDestination(for: URL.self) { urls, _ in
            debugLog(.library, "Dropped on the empty window: \(urls.map(\.lastPathComponent).joined(separator: ", "))")
            guard let url = urls.first else { return false }
            onOpen(url)
            return true
        } isTargeted: { targeted = $0 }
    }

    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: Metric.sp2) {
            Text(number).font(.caption.monospaced()).foregroundStyle(Native.muted)
            Text(title).bold()
            Text(detail).font(.caption).foregroundStyle(Native.fgSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metric.sp5)
        .background(Token.bg, in: RoundedRectangle(cornerRadius: Metric.rRow))
        .overlay(RoundedRectangle(cornerRadius: Metric.rRow).strokeBorder(Token.border))
    }
}
