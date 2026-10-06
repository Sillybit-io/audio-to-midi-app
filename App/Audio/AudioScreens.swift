import Foundation
import Observation

/// The Audio screen the window shows, plus at most one more that is kept alive in the background. Opening another file
/// while a run is going would otherwise cancel the run; instead its screen is parked and goes on transcribing, and
/// opening the file again brings it back with its progress or its result.
@MainActor @Observable
final class AudioScreens {
    private(set) var current: AudioScreenModel
    /// A screen whose run was going when another file was opened, or has finished since. Kept until the user comes back
    /// to its file or another run needs the slot; the result itself is already saved in the MIDI folder.
    private(set) var parked: AudioScreenModel?

    @ObservationIgnored private let make: @MainActor () -> AudioScreenModel

    init(make: @escaping @MainActor () -> AudioScreenModel) {
        self.make = make
        current = make()
        wire(current)
    }

    /// The audio file whose run is going, in whichever screen it lives.
    var transcribingURL: URL? {
        [current, parked].compactMap { $0 }.first { $0.session.isBusy }?.document.document?.url
    }

    func open(_ url: URL) {
        if let returning = parked, returning.document.document?.url == url {
            parked = nil
            if current.session.isBusy { park(current) }
            current.playback.stop()
            current = returning
            return
        }
        if current.session.isBusy, current.document.document?.url != url {
            park(current)
            current = make()
            wire(current)
        }
        current.document.open(url)
    }

    private func park(_ screen: AudioScreenModel) {
        screen.playback.stop()
        parked = screen
    }

    private func wire(_ screen: AudioScreenModel) {
        screen.otherRunInProgress = { [weak self, weak screen] in
            guard let self, let screen else { return false }
            return [current, parked].compactMap { $0 }.contains { $0 !== screen && $0.session.isBusy }
        }
    }
}
