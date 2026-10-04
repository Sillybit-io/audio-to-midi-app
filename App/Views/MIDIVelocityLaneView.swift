import SwiftUI

/// One bar per note, 72 pt tall. Dragging across the bars paints their velocities; the whole stroke is one undo step.
struct MIDIVelocityLaneView: View {
    let document: MIDIDocument
    let layout: PianoRollLayout

    @State private var stroke: [Int: Int] = [:]
    @State private var last: CGPoint?

    private static let reach: CGFloat = 5

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
            let height = max(2, usable * CGFloat(velocity) / 127)
            let bar = CGRect(x: x - 1.5, y: size.height - height, width: 3, height: height)
            let selected = document.selection.contains(note.id)
            let color = InstrumentColor.color(for: note.track).opacity(selected ? 1 : 0.6)
            context.fill(Path(roundedRect: bar, cornerRadius: 1.5), with: .color(color))
            if selected {
                context.fill(Path(ellipseIn: CGRect(x: x - 3, y: bar.minY - 3, width: 6, height: 6)), with: .color(color))
            }
        }
    }

    /// Notes whose start lies between the previous and current pointer positions take the value interpolated along the stroke.
    private func paint(from a: CGPoint, to b: CGPoint) {
        let low = min(a.x, b.x) - Self.reach, high = max(a.x, b.x) + Self.reach
        for note in document.notes where document.isVisible(note) {
            let x = layout.x(seconds: note.start)
            guard x >= low, x <= high else { continue }
            let t = b.x == a.x ? 1 : min(1, max(0, (x - a.x) / (b.x - a.x)))
            let y = a.y + (b.y - a.y) * t
            stroke[note.id] = MIDIEditing.clampedVelocity(Int(((1 - y / Metric.velH) * 127).rounded()))
        }
    }
}
