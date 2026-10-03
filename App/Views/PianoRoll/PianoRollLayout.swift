import CoreGraphics
import Foundation

/// Pure mapping between musical coordinates and view coordinates.
struct PianoRollLayout: Equatable, Sendable {
    var pixelsPerSecond: CGFloat = 100
    /// View-space x of time zero; negative once scrolled to the right.
    var xOrigin: CGFloat = 0
    var laneHeight: CGFloat = 8
    var topPitch = 127

    func x(seconds: Double) -> CGFloat { xOrigin + CGFloat(seconds) * pixelsPerSecond }
    func seconds(atX x: CGFloat) -> Double { Double((x - xOrigin) / pixelsPerSecond) }
    func y(pitch: Int) -> CGFloat { CGFloat(topPitch - pitch) * laneHeight }

    func rect(for note: NoteEvent) -> CGRect {
        CGRect(x: x(seconds: note.onset), y: y(pitch: note.pitch),
               width: max(1, CGFloat(note.offset - note.onset) * pixelsPerSecond), height: max(1, laneHeight - 1))
    }

    func visibleNotes(_ notes: [NoteEvent], from start: Double, to end: Double) -> [NoteEvent] {
        notes.filter { $0.offset >= start && $0.onset <= end }
    }

    func contentWidth(duration: Double) -> CGFloat { CGFloat(duration) * pixelsPerSecond }
}
