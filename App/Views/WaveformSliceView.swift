import SwiftUI

extension AudioSlice {
    enum Edge: Hashable { case start, end }

    /// Moves one edge by `delta` seconds. It stops at the other edge and at the ends of the audio.
    mutating func move(_ edge: Edge, by delta: Double) {
        switch edge {
        case .start: setStart(start + delta)
        case .end: setEnd(end + delta)
        }
    }

    /// Takes an edge as far as it can go: to the start of the audio or to the other edge for `.low`, the reverse for `.high`.
    mutating func jump(_ edge: Edge, toLowerLimit low: Bool) {
        switch (edge, low) {
        case (.start, true): setStart(0)
        case (.start, false): setStart(duration)
        case (.end, true): setEnd(0)
        case (.end, false): setEnd(duration)
        }
    }

    func position(of edge: Edge) -> Double {
        edge == .start ? start : end
    }
}

struct WaveformSliceView: View {
    @Bindable var model: DocumentModel
    @FocusState private var focusedEdge: AudioSlice.Edge?

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
                    handle(.start, at: x0) { model.slice.setStart($0 / width * duration) }
                    handle(.end, at: x1) { model.slice.setEnd($0 / width * duration) }
                }
            }
            .frame(height: 160)
            .accessibilityElement(children: .contain)
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

    private func title(_ edge: AudioSlice.Edge) -> String {
        edge == .start ? "Slice start" : "Slice end"
    }

    private func handle(_ edge: AudioSlice.Edge, at x: CGFloat, onDrag: @escaping (CGFloat) -> Void) -> some View {
        Rectangle().fill(Token.handle).frame(width: Metric.sp2)
            .overlay(Rectangle().fill(.clear).frame(width: Metric.sp6).contentShape(Rectangle()))
            .gesture(DragGesture(minimumDistance: 0).onChanged {
                focusedEdge = edge
                onDrag(x + $0.translation.width)
            })
            .focusable()
            .focused($focusedEdge, equals: edge)
            .onKeyPress(phases: [.down, .repeat]) { press in key(press, edge) }
            .accessibilityRepresentation {
                Slider(value: Binding(get: { model.slice.position(of: edge) },
                                      set: { value in adjust(edge) { $0.move(edge, by: value - $0.position(of: edge)) } }),
                       in: 0...max(model.slice.duration, AudioSlice.step), step: 0.1) { Text(title(edge)) }
                    .accessibilityValue(PlaybackEngine.timeText(seconds: model.slice.position(of: edge)))
                    .accessibilityHint("Left and right arrows move it by a tenth of a second, with Shift by a second. Home and End go to its limits.")
            }
            // Padding rather than `.offset`, so the element's frame (and its focus ring) sit where the handle is drawn.
            .padding(.leading, max(0, x - Metric.sp1))
    }

    private func key(_ press: KeyPress, _ edge: AudioSlice.Edge) -> KeyPress.Result {
        let step = press.modifiers.contains(.shift) ? 1.0 : 0.1
        switch press.key {
        case .leftArrow: adjust(edge) { $0.move(edge, by: -step) }
        case .rightArrow: adjust(edge) { $0.move(edge, by: step) }
        case .home: adjust(edge) { $0.jump(edge, toLowerLimit: true) }
        case .end: adjust(edge) { $0.jump(edge, toLowerLimit: false) }
        default: return .ignored
        }
        return .handled
    }

    /// Applies the change, then says where the edge ended up, which may differ from what was asked for.
    private func adjust(_ edge: AudioSlice.Edge, _ change: (inout AudioSlice) -> Void) {
        change(&model.slice)
        AccessibilityNotification.Announcement("\(title(edge)) \(PlaybackEngine.timeText(seconds: model.slice.position(of: edge)))").post()
    }
}
