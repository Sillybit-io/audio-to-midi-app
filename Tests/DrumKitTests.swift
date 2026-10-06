import Testing
@testable import SillyMIDITools

struct DrumKitTests {
    @Test func everyPitchBothDrumModelsEmitMapsToTheRightPiece() {
        let adtof: [(Int, DrumPiece)] = [(36, .kick), (38, .snare), (47, .toms), (42, .hiHat), (49, .cymbals)]
        let oaf: [(Int, DrumPiece)] = [(36, .kick), (38, .snare), (48, .toms), (42, .hiHat), (51, .cymbals), (53, .cymbals),
                                       (49, .cymbals), (75, .percussion)]
        for (pitch, piece) in adtof + oaf { #expect(DrumKit.piece(forPitch: pitch) == piece, "pitch \(pitch)") }
        #expect(DrumNotes.adtofPitches.count == 5 && DrumNotes.oafPitches.count == 8)
    }

    @Test func theWholeGeneralMidiKitIsCovered() {
        for pitch in 35...59 { #expect(DrumKit.name(forPitch: pitch).isEmpty == false) }
        #expect(DrumKit.piece(forPitch: 35) == .kick && DrumKit.piece(forPitch: 46) == .hiHat && DrumKit.piece(forPitch: 56) == .percussion)
        #expect(DrumKit.piece(forPitch: 99) == .percussion)
        #expect(DrumKit.name(forPitch: 99) == "Percussion 99")
    }

    @Test func laneLabelsFitTheKeyColumn() {
        for pitch in 35...75 { #expect(DrumKit.laneLabel(forPitch: pitch).count <= 9, "pitch \(pitch)") }
    }

    @Test func noTwoLanesShareAShortName() {
        let pitches = Array(35...59) + [64, 70, 75]
        let labels = pitches.map { DrumKit.laneLabel(forPitch: $0) }
        // The two kicks are one kit piece; every other pair of lanes must read differently.
        #expect(Set(labels).count == labels.count - 1)
    }

    @Test func lanesAreNamedOncePerPitchAndCountsFollowKitOrder() {
        let lanes = DrumKit.lanes(pitches: [38, 38, 36, 42, 42, 42])
        #expect(lanes.keys.sorted() == [36, 38, 42])
        #expect(lanes[38]?.label == "Snare" && lanes[36]?.label == "Kick" && lanes[42]?.label == "Hat")
        let counts = DrumKit.counts(pitches: [42, 36, 38, 42, 42, 49])
        #expect(counts.map(\.piece) == [.kick, .snare, .hiHat, .cymbals])
        #expect(counts.map(\.count) == [1, 1, 3, 1])
        #expect(DrumKit.counts(pitches: [Int]()).isEmpty)
    }

    @Test func everyPieceHasATitle() {
        #expect(DrumPiece.allCases.map(\.title) == ["Kick", "Snare", "Toms", "Hi-hat", "Cymbals", "Percussion"])
    }
}
