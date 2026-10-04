# Silly MIDI Tools

A native macOS app that turns audio into MIDI. Drop an audio file, pick a model, watch notes appear on a piano roll, play them back next to the original, and export a Standard MIDI File.

## Download and run

Get `SillyMIDITools-<version>-macOS-arm64.zip` from the [Releases](https://github.com/Sillybit-io/audio-to-midi-app/releases) page.

Requirements: macOS 26 or later on a Mac with Apple silicon (M1 or newer). Release builds are not built for Intel Macs; to run on Intel, build from source.

1. Unzip the file and move `SillyMIDITools.app` to `/Applications`.
2. The app is ad-hoc signed and not notarized, so Gatekeeper blocks the first launch. Clear the quarantine flag once:

   ```sh
   xattr -dr com.apple.quarantine /Applications/SillyMIDITools.app
   ```

   Or open the app, then go to System Settings, Privacy & Security, and choose **Open Anyway**. On recent macOS versions, right-click and Open no longer works for unsigned apps.
3. Open the app and drop an audio file onto the window, or press Command-O. WAV, MP3, FLAC, M4A, AIFF and anything else Core Audio decodes are supported.
4. Choose a model. Basic Pitch works straight away. The other models download on first use (see Models).
5. Press **Transcribe**.

## Features

- **Audio input.** Drop or open a file, see its waveform, and drag the handles to transcribe only a slice. Exported notes can keep the original timeline or start at zero.
- **Three engines.** MuScriptor (multi-instrument, drums included), Basic Pitch (fast, any pitched audio) and a piano model (high-resolution, piano only). The picker shows each model's licence.
- **Streaming piano roll.** Notes appear while a MuScriptor run is still going, coloured by instrument. Show or hide instruments with the legend. Cancel keeps the notes found so far.
- **Instruments, device and threads.** For MuScriptor you can restrict the transcription to chosen instruments, pick the compute device (Auto, a GPU, or CPU) and set the thread count.
- **Note velocity.** The piano model predicts velocity itself. For MuScriptor, which has none, a toggle (on by default) estimates velocity from the audio's loudness at each onset. Basic Pitch notes use the amplitude it reports.
- **Playback.** Play the notes through the built-in General MIDI sound bank, next to the original audio. Mix between the two with one slider, change the speed from 0.5x to 2x, and mute single instruments.
- **Key and scale detection.** Ranks major, minor, dorian, phrygian, lydian, mixolydian and locrian in all twelve keys, from the transcribed notes, or from the audio file with the Detect from audio button.
- **MIDI export.** Type 1 Standard MIDI File with one track per instrument. Drag the MIDI chip into Finder or a DAW, or use Export (Command-E). The export sheet can embed the model's licence notice in the file and add the detected key to the file name, for example `Song - Eb minor.mid`.
- **Licences in the app.** The About window lists every third-party component and its licence text.

## Models

| Model | Licence | Download | Use |
| --- | --- | --- | --- |
| MuScriptor small, medium, large (Mirelo and Kyutai; GGUF conversion by Damien Ronssin) | CC BY-NC 4.0 | 0.2 to 2.7 GB | Non-commercial use only |
| Piano (ONNX) (Kong et al., ONNX conversion by LanOss) | CC BY 4.0 | 154 MB | Piano only. Commercial use allowed with credit |
| Basic Pitch (Spotify) | Apache-2.0 | Built in | Commercial use allowed |

Downloads are pinned to a fixed revision and checked against a SHA-256 before use. Models are stored in the app's sandbox container under Application Support, and the picker can reveal or delete them.

MuScriptor weights are gated on Hugging Face. You need a Hugging Face account, you must accept the terms on the model page, and you paste a read token into Settings before the first download. The piano model is not gated.

## Build from source

Requirements: macOS 26 or later, Xcode 26 or later, `xcodegen`, `cmake` and `ninja`.

```sh
git clone --recurse-submodules https://github.com/Sillybit-io/audio-to-midi-app.git
cd audio-to-midi-app
scripts/build-engine.sh
xcodegen generate
xcodebuild -project SillyMIDITools.xcodeproj -scheme SillyMIDITools -destination 'platform=macOS' build CODE_SIGN_IDENTITY=-
```

Builds are for the host architecture only and are ad-hoc signed. To run the tests, replace `build` with `test`; the end-to-end piano tests need the model, which `scripts/fetch-piano-onnx.sh` downloads.

## Known limits

- Release builds are Apple silicon only, and are not notarized.
- The piano model handles one instrument; on other music it reports piano notes for whatever it hears.
- Velocity estimated for MuScriptor is relative loudness, not a measurement of how hard a note was played.
- Key detection ranks likely keys; modes that share most of their notes (for example dorian and natural minor) can be close.
- OGG files are not decoded.
- Export uses a fixed 120 bpm, 4/4 grid.

## Licence

The app code is licensed under the Apache License 2.0, see `LICENSE`. Third-party components and model licences are listed in `THIRD_PARTY_NOTICES.md`.
