import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let onOpen: (URL) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.plus").font(.system(size: 48))
            Text("Drop an audio file here").font(.title2)
            Text("or press Command-O").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(targeted ? Color.accentColor.opacity(0.15) : .clear)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(targeted ? Color.accentColor : .secondary)
                .padding(24)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            onOpen(url)
            return true
        } isTargeted: { targeted = $0 }
    }
}
