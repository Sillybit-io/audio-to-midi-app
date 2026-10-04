import SwiftUI

struct WaveformSliceView: View {
    @Bindable var model: DocumentModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let duration = max(model.slice.duration, 0.01)
                let x0 = width * model.slice.start / duration
                let x1 = width * model.slice.end / duration
                ZStack(alignment: .leading) {
                    Canvas { context, size in
                        let mid = size.height / 2
                        for (i, peak) in model.peaks.enumerated() {
                            let x = size.width * (Double(i) + 0.5) / Double(max(model.peaks.count, 1))
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: mid - CGFloat(peak.max) * mid))
                            path.addLine(to: CGPoint(x: x, y: mid - CGFloat(peak.min) * mid))
                            context.stroke(path, with: .color(Token.waveSel), lineWidth: Metric.hairline)
                        }
                    }
                    Rectangle().fill(Token.regionDim).frame(width: x0)
                    Rectangle().fill(Token.regionDim).frame(width: max(0, width - x1)).offset(x: x1)
                    handle(at: x0) { model.slice.setStart($0 / width * duration) }
                    handle(at: x1) { model.slice.setEnd($0 / width * duration) }
                }
            }
            .frame(height: 160)
            .accessibilityLabel("Waveform")
            HStack {
                Text(String(format: "%@ — selected %.2f s of %.2f s", model.document?.name ?? "", model.slice.span, model.slice.duration))
                Spacer()
                Toggle("Original timeline", isOn: Binding(
                    get: { !model.slice.relativeTimeline },
                    set: { model.slice.relativeTimeline = !$0 }))
                Button("Reset") { model.slice.reset() }
            }
        }
        .padding()
    }

    private func handle(at x: CGFloat, onDrag: @escaping (CGFloat) -> Void) -> some View {
        Rectangle().fill(Token.handle).frame(width: Metric.sp2)
            .overlay(Rectangle().fill(.clear).frame(width: Metric.sp6).contentShape(Rectangle()))
            .offset(x: x - Metric.sp1)
            .gesture(DragGesture(minimumDistance: 0).onChanged { onDrag(x + $0.translation.width) })
    }
}
