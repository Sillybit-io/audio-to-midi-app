import SwiftUI

struct KeyView: View {
    let notes: [NoteEvent]
    let audio: () -> (samples: [Float], rate: Double)?
    @State private var fromAudio: [KeyMatch] = []
    @State private var busy = false

    private var fromNotes: [KeyMatch] { KeyDetector.rank(notes: notes) }

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.sp5) {
            list("Key from notes", fromNotes)
            VStack(alignment: .leading, spacing: Metric.sp2) {
                HStack {
                    Text("Key from audio").bold()
                    Spacer()
                    Button(busy ? "Analysing…" : "Detect from audio") {
                        guard let a = audio() else { return }
                        busy = true
                        Task {
                            let result = await Task.detached { KeyDetector.rank(samples: a.samples, sampleRate: a.rate) }.value
                            fromAudio = result
                            busy = false
                        }
                    }.disabled(busy)
                }
                matches(fromAudio)
            }
        }
        .font(.caption)
    }

    @ViewBuilder private func list(_ title: String, _ items: [KeyMatch]) -> some View {
        VStack(alignment: .leading, spacing: Metric.sp1) {
            Text(title).bold()
            matches(items)
        }
    }

    @ViewBuilder private func matches(_ items: [KeyMatch]) -> some View {
        if items.isEmpty { Text("—").foregroundStyle(Native.fgSecondary) }
        ForEach(items.prefix(3)) { Text("\($0.name)  \(Int(($0.score * 100).rounded()))%") }
    }
}
