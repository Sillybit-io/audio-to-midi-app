import CoreGraphics
import Testing
@testable import SillyMIDITools

struct PianoRollLayoutTests {
    private func note(_ onset: Double, _ offset: Double, _ pitch: Int) -> NoteEvent {
        NoteEvent(onset: onset, offset: offset, pitch: pitch, program: 0, isDrum: false, instrument: "acoustic_piano", velocity: nil, pitchBends: nil)
    }

    @Test func mapsTimeToX() {
        let layout = PianoRollLayout(pixelsPerSecond: 100, xOrigin: 200)
        #expect(layout.x(seconds: 2) == 400)
        #expect(layout.seconds(atX: 400) == 2)
    }

    @Test func mapsPitchToY() {
        let layout = PianoRollLayout(laneHeight: 8, topPitch: 127)
        #expect(layout.y(pitch: 60) == 536)
    }

    @Test func rectSpansTheNoteDuration() {
        let layout = PianoRollLayout(pixelsPerSecond: 100, xOrigin: 0, laneHeight: 8)
        let r = layout.rect(for: note(1, 1.5, 60))
        #expect(r.minX == 100)
        #expect(r.width == 50)
    }

    @Test func visibleRangeReturnsOnlyOverlappingNotes() {
        let layout = PianoRollLayout()
        let notes = [note(0, 1, 60), note(4, 5, 62), note(9, 10, 64)]
        #expect(layout.visibleNotes(notes, from: 3.5, to: 6).map(\.pitch) == [62])
    }
}
