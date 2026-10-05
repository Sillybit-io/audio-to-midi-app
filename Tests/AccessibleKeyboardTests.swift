import Foundation
import Testing
@testable import SillyMIDITools

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

struct SliceKeyboardTests {
    @Test func arrowsMoveAnEdgeByATenthAndShiftByASecond() {
        var slice = AudioSlice(duration: 10)
        slice.move(.start, by: 0.1)
        #expect(near(slice.start, 0.1))
        slice.move(.start, by: 0.1)
        #expect(near(slice.start, 0.2))
        slice.move(.start, by: 1)
        #expect(near(slice.start, 1.2))
        slice.move(.end, by: -0.1)
        #expect(near(slice.end, 9.9))
        slice.move(.end, by: -1)
        #expect(near(slice.end, 8.9))
        slice.move(.start, by: -0.1)
        #expect(near(slice.start, 1.1))
    }

    @Test func homeAndEndReachTheLimitsOfEachEdge() {
        var slice = AudioSlice(duration: 10)
        slice.move(.start, by: 4)
        slice.move(.end, by: -3)
        #expect(near(slice.start, 4) && near(slice.end, 7))

        slice.jump(.start, toLowerLimit: true)
        #expect(slice.start == 0)
        slice.jump(.start, toLowerLimit: false)
        #expect(near(slice.start, 7 - AudioSlice.minimumSpan))
        slice.jump(.end, toLowerLimit: false)
        #expect(slice.end == 10)
        slice.jump(.end, toLowerLimit: true)
        #expect(near(slice.end, slice.start + AudioSlice.minimumSpan))
    }

    @Test func movingTheStartPastTheEndStopsJustBeforeIt() {
        var slice = AudioSlice(duration: 10)
        slice.move(.end, by: -8)
        #expect(near(slice.end, 2))
        slice.move(.start, by: 5)
        #expect(near(slice.start, 2 - AudioSlice.minimumSpan))
        #expect(slice.start < slice.end)
        #expect(near(slice.position(of: .start), slice.start) && near(slice.position(of: .end), 2))
    }

    @Test func movingTheEndBeforeTheStartAndPastTheAudioStopsAtTheLimits() {
        var slice = AudioSlice(duration: 10)
        slice.move(.start, by: 3)
        slice.move(.end, by: -9)
        #expect(near(slice.end, 3 + AudioSlice.minimumSpan))
        slice.move(.end, by: 50)
        #expect(slice.end == 10)
        slice.move(.start, by: -50)
        #expect(slice.start == 0)
        #expect(slice.span > 0)
    }
}

@MainActor
struct NoteSteppingTests {
    private func document() -> MIDIDocument {
        let tracks = [MIDITrack(id: "piano", name: "piano", program: 0, isDrums: false),
                      MIDITrack(id: "bass", name: "bass", program: 33, isDrums: false)]
        let notes = [EditorNote(id: 1, track: "piano", pitch: 64, start: 1, duration: 0.5, velocity: 90),
                     EditorNote(id: 2, track: "piano", pitch: 60, start: 0, duration: 0.5, velocity: 80),
                     EditorNote(id: 3, track: "bass", pitch: 36, start: 0, duration: 1, velocity: 70),
                     EditorNote(id: 4, track: "piano", pitch: 67, start: 2, duration: 0.5, velocity: 100)]
        return MIDIDocument(sourceName: "steps.mid", tracks: tracks, notes: notes)
    }

    @Test func steppingForwardWalksTheNotesInTimeOrder() {
        let document = document()
        #expect(document.selectAdjacent(1)?.id == 3)
        #expect(document.selection == [3])
        #expect(document.selectAdjacent(1)?.id == 2)
        #expect(document.selectAdjacent(1)?.id == 1)
        #expect(document.selectAdjacent(1)?.id == 4)
        #expect(document.selectAdjacent(1)?.id == 4)
        #expect(document.selection == [4])
    }

    @Test func steppingBackwardStartsAtTheLastNoteAndStopsAtTheFirst() {
        let document = document()
        #expect(document.selectAdjacent(-1)?.id == 4)
        #expect(document.selectAdjacent(-1)?.id == 1)
        #expect(document.selectAdjacent(-1)?.id == 2)
        #expect(document.selectAdjacent(-1)?.id == 3)
        #expect(document.selectAdjacent(-1)?.id == 3)
    }

    @Test func hiddenTracksAreSkippedAndAnEmptyDocumentSelectsNothing() {
        let document = document()
        document.toggleHidden("bass")
        #expect(document.selectAdjacent(1)?.id == 2)
        #expect(document.selectAdjacent(1)?.id == 1)

        let empty = MIDIDocument(sourceName: "empty.mid", tracks: [], notes: [])
        #expect(empty.selectAdjacent(1) == nil && empty.selection.isEmpty)
        #expect(!document.isDirty && !document.isEdited && !document.canUndo)
    }
}

struct SliceGestureTests {
    @Test func aSliceIsNeverShorterThanHalfASecond() {
        var slice = AudioSlice(duration: 10)
        slice.setStart(9.9)
        #expect(near(slice.start, 9.5) && slice.end == 10)
        var short = AudioSlice(duration: 0.3)
        short.setStart(0.2)
        #expect(short.start == 0 && near(short.end, 0.3))
    }

    @Test func draggingAcrossEmptyTrackSelectsANewSliceInEitherDirection() {
        var slice = AudioSlice(duration: 10)
        slice.select(from: 6, to: 2)
        #expect(near(slice.start, 2) && near(slice.end, 6))
        slice.select(from: 3, to: 3.1)
        #expect(near(slice.start, 3) && near(slice.end, 3.5))
        slice.select(from: 9.9, to: 12)
        #expect(near(slice.start, 9.5) && slice.end == 10)
        #expect(slice.contains(9.7) && !slice.contains(9))
    }

    @Test func draggingInsideMovesTheSliceAndKeepsItsLength() {
        var slice = AudioSlice(duration: 10)
        slice.select(from: 2, to: 5)
        slice.shift(by: 1.5)
        #expect(near(slice.start, 3.5) && near(slice.end, 6.5))
        slice.shift(by: 20)
        #expect(near(slice.start, 7) && slice.end == 10)
        slice.shift(by: -20)
        #expect(slice.start == 0 && near(slice.end, 3))
    }

    @Test func theWaveformHeaderAndRulerReadLikeThePrototype() {
        var slice = AudioSlice(duration: 16)
        slice.select(from: 2, to: 12)
        #expect(WaveformSliceView.selectionText(slice) == "Selected 10.0 s of 16.0 s")
        #expect(WaveformSliceView.tickStep(duration: 16, width: 640) == 2)
        #expect(WaveformSliceView.tickStep(duration: 3, width: 640) == 1)
        #expect(WaveformSliceView.tickStep(duration: 150, width: 640) == 15)
        // A 20-minute file in the same width: labels at least 48 pt apart, so every 2 minutes, not every 30 s.
        #expect(WaveformSliceView.tickStep(duration: 1200, width: 640) == 120)
        #expect(WaveformSliceView.tickStep(duration: 1200, width: 1000) == 60)
    }
}
