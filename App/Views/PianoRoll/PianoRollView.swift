import SwiftUI

struct PianoRollView: View {
    let notes: [NoteEvent]
    let duration: Double
    let finalizedThrough: Double
    var playhead: Double?
    let hidden: Set<String>
    @Binding var pixelsPerSecond: CGFloat
    var showsEmptyState = false

    @State private var zoomAtStart: CGFloat?
    @State private var offset = CGPoint.zero

    static let lowPitch = 21
    static let highPitch = 108
    /// The export grid is fixed at 120 BPM in 4/4: one bar is two seconds.
    static let secondsPerBar = 2.0

    private static let blackKeys: Set<Int> = [1, 3, 6, 8, 10]

    var body: some View {
        GeometryReader { proxy in
            let layout = PianoRollLayout(pixelsPerSecond: pixelsPerSecond, xOrigin: -offset.x,
                                         laneHeight: Metric.rowH, topPitch: Self.highPitch)
            let contentWidth = max(proxy.size.width - Metric.keysW, layout.contentWidth(duration: duration) + Metric.sp10)
            let contentHeight = CGFloat(Self.highPitch - Self.lowPitch + 1) * Metric.rowH
            let xOffset = offset.x, yOffset = offset.y
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Token.surfaceSunken.frame(width: Metric.keysW, height: Metric.rulerH)
                    Canvas { context, size in drawRuler(context, size, layout) }
                        .frame(height: Metric.rulerH).background(Token.surfaceSunken)
                }
                HStack(spacing: 0) {
                    Canvas { context, size in drawKeys(context, size, yOffset: yOffset) }
                        .frame(width: Metric.keysW)
                    ZStack {
                        ScrollView([.horizontal, .vertical]) {
                            Color.clear.frame(width: contentWidth, height: contentHeight)
                        }
                        .defaultScrollAnchor(UnitPoint(x: 0, y: 0.62))
                        .onScrollGeometryChange(for: CGPoint.self) { $0.contentOffset } action: { _, new in
                            offset = CGPoint(x: max(0, new.x), y: max(0, new.y))
                        }
                        .overlay {
                            Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, size in
                                draw(context, size, layout, xOffset: xOffset, yOffset: yOffset)
                            }
                            .allowsHitTesting(false)
                        }
                        .gesture(MagnifyGesture().onChanged { value in
                            let base = zoomAtStart ?? pixelsPerSecond
                            zoomAtStart = base
                            pixelsPerSecond = min(1000, max(10, base * value.magnification))
                        }.onEnded { _ in zoomAtStart = nil })
                        if showsEmptyState { emptyState }
                    }
                }
            }
            .background(Token.surface)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Piano roll")
            .accessibilityValue("\(notes.count) notes")
        }
    }

    private var emptyState: some View {
        VStack(spacing: Metric.sp4) {
            Image(systemName: "waveform.badge.plus").font(.largeTitle).foregroundStyle(Native.fgSecondary)
            Text("Ready to Transcribe").font(.title2.bold())
            Text("Drag the handles to transcribe only a slice, pick a model, then press Transcribe. Notes appear here as the model works.")
                .multilineTextAlignment(.center).foregroundStyle(Native.fgSecondary)
            Text("↩").foregroundStyle(Native.muted)
        }
        .padding(Metric.sp8)
        .frame(maxWidth: Metric.sheetW)
        .background(Token.surfaceRaised.opacity(0.92), in: RoundedRectangle(cornerRadius: Metric.rPanel))
        .overlay(RoundedRectangle(cornerRadius: Metric.rPanel).strokeBorder(Token.border))
        .accessibilityElement(children: .combine)
    }

    private func isBlack(_ pitch: Int) -> Bool { Self.blackKeys.contains(pitch % 12) }

    private func drawRuler(_ context: GraphicsContext, _ size: CGSize, _ layout: PianoRollLayout) {
        let firstBar = max(0, Int(layout.seconds(atX: 0) / Self.secondsPerBar))
        let lastBar = Int(layout.seconds(atX: size.width) / Self.secondsPerBar) + 1
        for bar in firstBar...max(firstBar, lastBar) {
            let x = layout.x(seconds: Double(bar) * Self.secondsPerBar)
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: size.height * 0.45))
            tick.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(tick, with: .color(Token.gridBar), lineWidth: Metric.hairline)
            context.draw(Text("\(bar + 1)").font(.system(size: TypeScale.caption)).foregroundStyle(Native.fgSecondary),
                         at: CGPoint(x: x + Metric.sp2, y: size.height * 0.3), anchor: .leading)
        }
    }

    private func drawKeys(_ context: GraphicsContext, _ size: CGSize, yOffset: CGFloat) {
        for pitch in Self.lowPitch...Self.highPitch {
            let y = CGFloat(Self.highPitch - pitch) * Metric.rowH - yOffset
            guard y + Metric.rowH >= 0, y <= size.height else { continue }
            let width = isBlack(pitch) ? size.width * 0.6 : size.width
            context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: Metric.rowH)), with: .color(Token.keyWhite))
            if isBlack(pitch) {
                context.fill(Path(CGRect(x: 0, y: y, width: width, height: Metric.rowH)), with: .color(Token.keyBlack))
            }
            if pitch % 12 == 0 {
                context.draw(Text("C\(pitch / 12 - 1)").font(.system(size: TypeScale.micro)).foregroundStyle(Token.keyLabel),
                             at: CGPoint(x: size.width - Metric.sp2, y: y + Metric.rowH / 2), anchor: .trailing)
            }
        }
    }

    private func draw(_ context: GraphicsContext, _ size: CGSize, _ layout: PianoRollLayout, xOffset: CGFloat, yOffset: CGFloat) {
        var context = context
        context.translateBy(x: 0, y: -yOffset)
        let top = yOffset, bottom = yOffset + size.height
        for pitch in Self.lowPitch...Self.highPitch {
            let y = layout.y(pitch: pitch)
            guard y + Metric.rowH >= top, y <= bottom else { continue }
            if isBlack(pitch) {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: Metric.rowH)), with: .color(Token.gridBeat))
            }
            if pitch % 12 == 0 {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y + Metric.rowH))
                line.addLine(to: CGPoint(x: size.width, y: y + Metric.rowH))
                context.stroke(line, with: .color(Token.gridBar), lineWidth: Metric.hairline)
            }
        }
        let beat = Self.secondsPerBar / 4
        let firstBeat = max(0, Int(layout.seconds(atX: 0) / beat))
        let lastBeat = Int(layout.seconds(atX: size.width) / beat) + 1
        for index in firstBeat...max(firstBeat, lastBeat) {
            let x = layout.x(seconds: Double(index) * beat)
            var line = Path()
            line.move(to: CGPoint(x: x, y: top))
            line.addLine(to: CGPoint(x: x, y: bottom))
            context.stroke(line, with: .color(index % 4 == 0 ? Token.gridBar : Token.gridBeat), lineWidth: Metric.hairline)
        }
        let visible = layout.visibleNotes(notes, from: layout.seconds(atX: 0), to: layout.seconds(atX: size.width))
        for note in visible where !hidden.contains(note.instrument) && (Self.lowPitch...Self.highPitch).contains(note.pitch) {
            let path = Path(roundedRect: layout.rect(for: note), cornerRadius: Metric.rNote)
            context.fill(path, with: .color(InstrumentColor.color(for: note.instrument)))
            context.stroke(path, with: .color(Token.noteEdge), lineWidth: Metric.hairline)
        }
        if finalizedThrough > 0 { line(context, x: layout.x(seconds: finalizedThrough), top: top, bottom: bottom, color: Native.fgSecondary) }
        if let playhead { line(context, x: layout.x(seconds: playhead), top: top, bottom: bottom, color: Token.playhead) }
    }

    private func line(_ context: GraphicsContext, x: CGFloat, top: CGFloat, bottom: CGFloat, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: x, y: top))
        path.addLine(to: CGPoint(x: x, y: bottom))
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }
}
