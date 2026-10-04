import CoreGraphics
import Foundation

/// The editor's snap grid. The export grid is fixed at 120 BPM in 4/4, so a quarter note is half a second.
enum SnapGrid: Double, CaseIterable, Identifiable, Sendable {
    case quarter = 0.5
    case eighth = 0.25
    case sixteenth = 0.125
    case thirtySecond = 0.0625
    case off = 0

    var id: Double { rawValue }
    var step: Double { rawValue }

    var title: String {
        switch self {
        case .quarter: "1/4 note"
        case .eighth: "1/8 note"
        case .sixteenth: "1/16 note"
        case .thirtySecond: "1/32 note"
        case .off: "Off"
        }
    }
}

enum MIDIHit: Equatable, Sendable {
    case body(Int)
    case resizeEdge(Int)

    var id: Int {
        switch self {
        case .body(let id), .resizeEdge(let id): id
        }
    }
}

/// Pure edits on note values. Each returns the new notes, or nil when the edit is rejected or would change nothing,
/// so a caller can tell a real change from a no-op without comparing arrays.
enum MIDIEditing {
    /// C1 to B6.
    static let pitchRange = 24...95
    static let velocityRange = 1...127
    static let defaultVelocity = 100
    static let secondsPerBeat = 0.5
    static let secondsPerBar = 2.0
    /// The shortest note when the grid is off.
    static let minimumDuration = 0.03
    static let resizeEdgeWidth: CGFloat = 6

    static func snap(_ seconds: Double, to grid: SnapGrid) -> Double {
        grid == .off ? seconds : (seconds / grid.step).rounded() * grid.step
    }

    static func snapFloor(_ seconds: Double, to grid: SnapGrid) -> Double {
        grid == .off ? seconds : (seconds / grid.step).rounded(.down) * grid.step
    }

    static func minimumLength(on grid: SnapGrid) -> Double {
        grid == .off ? minimumDuration : grid.step
    }

    static func clampedVelocity(_ value: Int) -> Int {
        min(max(value, velocityRange.lowerBound), velocityRange.upperBound)
    }

    /// A new note at `time` floored to the grid. Rejected outside C1–B6 or before time zero.
    static func draw(at time: Double, pitch: Int, track: String, id: Int, grid: SnapGrid, length: Double? = nil) -> EditorNote? {
        guard time.isFinite, time >= 0, pitchRange.contains(pitch) else { return nil }
        let duration: Double
        if let length, length.isFinite {
            duration = max(minimumLength(on: grid), snap(length, to: grid))
        } else {
            duration = grid == .off ? 0.25 : grid.step
        }
        return EditorNote(id: id, track: track, pitch: pitch, start: snapFloor(time, to: grid), duration: duration, velocity: defaultVelocity)
    }

    static func erase(_ notes: [EditorNote], ids: Set<Int>) -> [EditorNote]? {
        guard notes.contains(where: { ids.contains($0.id) }) else { return nil }
        return notes.filter { !ids.contains($0.id) }
    }

    /// Moves the group by whole grid steps. The group stops at time zero and at C1/B6 instead of bending its shape.
    static func move(_ notes: [EditorNote], ids: Set<Int>, deltaTime: Double, deltaPitch: Int, grid: SnapGrid) -> [EditorNote]? {
        let moving = notes.filter { ids.contains($0.id) }
        guard let earliest = moving.map(\.start).min(), let lowest = moving.map(\.pitch).min(),
              let highest = moving.map(\.pitch).max(), deltaTime.isFinite else { return nil }
        let time = max(snap(deltaTime, to: grid), -earliest)
        let semitones = min(max(deltaPitch, pitchRange.lowerBound - lowest), pitchRange.upperBound - highest)
        guard time != 0 || semitones != 0 else { return nil }
        return notes.map { note in
            guard ids.contains(note.id) else { return note }
            var moved = note
            moved.start += time
            moved.pitch += semitones
            return moved
        }
    }

    static func transpose(_ notes: [EditorNote], ids: Set<Int>, by semitones: Int) -> [EditorNote]? {
        move(notes, ids: ids, deltaTime: 0, deltaPitch: semitones, grid: .off)
    }

    /// Shifts by `steps` grid steps (an eighth of a second when the grid is off).
    static func nudge(_ notes: [EditorNote], ids: Set<Int>, steps: Int, grid: SnapGrid) -> [EditorNote]? {
        let step = grid == .off ? 0.125 : grid.step
        return move(notes, ids: ids, deltaTime: Double(steps) * step, deltaPitch: 0, grid: .off)
    }

    /// Changes each note's length by `delta`, snapped, never below the shortest note the grid allows.
    static func resize(_ notes: [EditorNote], ids: Set<Int>, delta: Double, grid: SnapGrid) -> [EditorNote]? {
        guard delta.isFinite else { return nil }
        let floor = minimumLength(on: grid)
        var changed = false
        let result = notes.map { note in
            guard ids.contains(note.id) else { return note }
            var resized = note
            resized.duration = max(floor, snap(note.duration + delta, to: grid))
            if resized.duration != note.duration { changed = true }
            return resized
        }
        return changed ? result : nil
    }

    /// Snaps starts and ends to the grid. `ids` nil means every note.
    static func quantize(_ notes: [EditorNote], ids: Set<Int>?, grid: SnapGrid) -> [EditorNote]? {
        guard grid != .off else { return nil }
        var changed = false
        let result = notes.map { note in
            guard ids?.contains(note.id) ?? true else { return note }
            var quantized = note
            let end = snap(note.end, to: grid)
            quantized.start = snap(note.start, to: grid)
            quantized.duration = max(grid.step, end - quantized.start)
            if quantized != note { changed = true }
            return quantized
        }
        return changed ? result : nil
    }

    static func setVelocity(_ notes: [EditorNote], ids: Set<Int>, to value: Int) -> [EditorNote]? {
        let velocity = clampedVelocity(value)
        var changed = false
        let result = notes.map { note in
            guard ids.contains(note.id), note.velocity != velocity else { return note }
            var painted = note
            painted.velocity = velocity
            changed = true
            return painted
        }
        return changed ? result : nil
    }

    /// Sets the velocity of every visible note that starts inside the painted time span.
    static func paintVelocity(_ notes: [EditorNote], from: Double, to: Double, value: Int, hiddenTracks: Set<String>) -> [EditorNote]? {
        let span = min(from, to)...max(from, to)
        let ids = Set(notes.filter { span.contains($0.start) && !hiddenTracks.contains($0.track) }.map(\.id))
        return setVelocity(notes, ids: ids, to: value)
    }

    /// Visible notes that overlap the rectangle in time and pitch.
    static func notes(inTime time: ClosedRange<Double>, pitches: ClosedRange<Int>, among notes: [EditorNote], hiddenTracks: Set<String>) -> Set<Int> {
        Set(notes.filter { note in
            !hiddenTracks.contains(note.track) && pitches.contains(note.pitch)
                && note.start < time.upperBound && note.end > time.lowerBound
        }.map(\.id))
    }

    /// The topmost visible note under `point`, and whether the point is on its right-edge resize handle.
    static func hit(at point: CGPoint, notes: [EditorNote], layout: PianoRollLayout, hiddenTracks: Set<String>) -> MIDIHit? {
        for note in notes.reversed() where !hiddenTracks.contains(note.track) {
            let rect = layout.rect(for: NoteEvent(onset: note.start, offset: note.end, pitch: note.pitch, program: 0, isDrum: false,
                                                  instrument: note.track, velocity: note.velocity, pitchBends: nil))
            guard rect.contains(point) else { continue }
            let edge = min(resizeEdgeWidth, rect.width / 2)
            return point.x >= rect.maxX - edge ? .resizeEdge(note.id) : .body(note.id)
        }
        return nil
    }
}
