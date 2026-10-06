import SwiftUI

/// One bar per note, 72 pt tall. Dragging across the bars paints their velocities; the whole stroke is one undo step.
struct MIDIVelocityLaneView: View {
    let document: MIDIDocument
    let layout: PianoRollLayout
    var colour: (EditorNote) -> Color = { InstrumentColor.color(for: $0.track) }

    @State private var stroke: [Int: Int] = [:]
    @State private var last: CGPoint?

    private static let reach = Metric.velReach

    var body: some View {
        Canvas { context, size in
            draw(context, size)
        }
        .frame(height: Metric.velH)
        .background(Token.surfaceSunken)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    paint(from: last ?? value.location, to: value.location)
                    last = value.location
                }
                .onEnded { _ in
                    document.setVelocities(stroke)
                    stroke = [:]
                    last = nil
                }
        )
        .accessibilityLabel("Velocity lane")
        .accessibilityHint("Drag across the bars to set note velocities")
    }

    private func draw(_ context: GraphicsContext, _ size: CGSize) {
        let usable = size.height - Metric.sp4
        for note in document.notes where document.isVisible(note) {
            let x = layout.x(seconds: note.start)
            guard x >= -Self.reach, x <= size.width + Self.reach else { continue }
            let velocity = stroke[note.id] ?? note.velocity
            let height = max(Metric.velBarMinH, usable * CGFloat(velocity) / 127)
            let bar = CGRect(x: x - Metric.velBarW / 2, y: size.height - height, width: Metric.velBarW, height: height)
            let selected = document.selection.contains(note.id)
            let color = colour(note).opacity(selected ? 1 : 0.6)
            context.fill(Path(roundedRect: bar, cornerRadius: Metric.velBarW / 2), with: .color(color))
            if selected {
                context.fill(Path(ellipseIn: CGRect(x: x - Metric.velDot / 2, y: bar.minY - Metric.velDot / 2, width: Metric.velDot, height: Metric.velDot)), with: .color(color))
            }
        }
    }

    /// Notes whose start lies between the previous and current pointer positions take the value interpolated along the stroke.
    private func paint(from a: CGPoint, to b: CGPoint) {
        stroke.merge(Self.stroke(from: a, to: b, notes: document.notes, layout: layout, selection: document.selection,
                                 hiddenTracks: document.hiddenTracks)) { _, new in new }
    }

    /// The velocities a stroke segment sets: visible notes whose start lies under it, only selected ones when there is a
    /// selection, each taking the height interpolated along the segment.
    static func stroke(from a: CGPoint, to b: CGPoint, notes: [EditorNote], layout: PianoRollLayout, selection: Set<Int>,
                       hiddenTracks: Set<String>) -> [Int: Int] {
        let low = min(a.x, b.x) - reach, high = max(a.x, b.x) + reach
        var values: [Int: Int] = [:]
        for note in notes where !hiddenTracks.contains(note.track) && (selection.isEmpty || selection.contains(note.id)) {
            let x = layout.x(seconds: note.start)
            guard x >= low, x <= high else { continue }
            let t = b.x == a.x ? 1 : min(1, max(0, (x - a.x) / (b.x - a.x)))
            let y = a.y + (b.y - a.y) * t
            values[note.id] = MIDIEditing.clampedVelocity(Int(((1 - y / Metric.velH) * 127).rounded()))
        }
        return values
    }
}
