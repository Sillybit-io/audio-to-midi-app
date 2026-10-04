import SwiftUI

struct KeyView: View {
    let notes: [NoteEvent]
    let audio: () -> (samples: [Float], rate: Double)?
    @State private var fromAudio: [KeyMatch] = []
    @State private var busy = false

    private var fromNotes: [KeyMatch] { KeyDetector.rank(notes: notes) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            list("Key from notes", fromNotes)
            list("Key from audio", fromAudio)
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
        .font(.caption)
    }

    @ViewBuilder private func list(_ title: String, _ matches: [KeyMatch]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).bold()
            if matches.isEmpty { Text("—").foregroundStyle(.secondary) }
            ForEach(matches.prefix(3)) { Text("\($0.name)  \(Int(($0.score * 100).rounded()))%") }
        }
    }
}
