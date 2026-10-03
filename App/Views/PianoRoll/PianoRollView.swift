import SwiftUI

struct PianoRollView: View {
    let notes: [NoteEvent]
    let duration: Double
    let finalizedThrough: Double
    var playhead: Double?
    let hidden: Set<String>

    @State private var pixelsPerSecond: CGFloat = 100
    @State private var zoomAtStart: CGFloat?
    @State private var offset: CGFloat = 0

    private static let lowPitch = 21
    private static let highPitch = 108

    var body: some View {
        GeometryReader { proxy in
            let lanes = CGFloat(Self.highPitch - Self.lowPitch + 1)
            let layout = PianoRollLayout(pixelsPerSecond: pixelsPerSecond, xOrigin: -offset,
                                         laneHeight: max(2, proxy.size.height / lanes), topPitch: Self.highPitch)
            ScrollView(.horizontal) {
                Color.clear.frame(width: max(proxy.size.width, layout.contentWidth(duration: duration)), height: 1)
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, new in offset = max(0, new) }
            .overlay {
                Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, size in
                    draw(context, size, layout)
                }
                .allowsHitTesting(false)
            }
            .gesture(MagnifyGesture().onChanged { value in
                let base = zoomAtStart ?? pixelsPerSecond
                zoomAtStart = base
                pixelsPerSecond = min(1000, max(10, base * value.magnification))
            }.onEnded { _ in zoomAtStart = nil })
            .background(Color(nsColor: .textBackgroundColor))
            .accessibilityElement()
            .accessibilityLabel("\(notes.count) notes")
        }
    }

    private func draw(_ context: GraphicsContext, _ size: CGSize, _ layout: PianoRollLayout) {
        for pitch in Self.lowPitch...Self.highPitch where pitch % 12 == 0 {
            let y = layout.y(pitch: pitch)
            context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: layout.laneHeight)), with: .color(.gray.opacity(0.12)))
        }
        let visible = layout.visibleNotes(notes, from: layout.seconds(atX: 0), to: layout.seconds(atX: size.width))
        for note in visible where !hidden.contains(note.instrument) && (Self.lowPitch...Self.highPitch).contains(note.pitch) {
            let rect = layout.rect(for: note)
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(InstrumentColor.color(for: note.instrument)))
        }
        line(context, size, x: layout.x(seconds: finalizedThrough), color: .secondary)
        if let playhead { line(context, size, x: layout.x(seconds: playhead), color: .red) }
    }

    private func line(_ context: GraphicsContext, _ size: CGSize, x: CGFloat, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }
}
