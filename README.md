# Silly MIDI Tools

A native macOS app that turns audio into MIDI. Drop an audio file, pick a model, watch notes appear on a piano roll, play them back next to the original, and export a Standard MIDI File.

## Download and run

Get `SillyMIDITools-<version>-macOS-arm64.zip` from the [Releases](https://github.com/Sillybit-io/audio-to-midi-app/releases) page.

Requirements: macOS 26 or later on a Mac with Apple silicon (M1 or newer). Release builds are not built for Intel Macs; to run on Intel, build from source.

1. Unzip the file by double-clicking it in Finder, or run `ditto -x -k <zip file> .`. Plain `unzip` drops signature data from the bundled Metal libraries. Move `SillyMIDITools.app` to `/Applications`.
2. The app is ad-hoc signed and not notarized, so Gatekeeper blocks the first launch. Clear the quarantine flag once:

   ```sh
   xattr -dr com.apple.quarantine /Applications/SillyMIDITools.app
   ```

   Or open the app, then go to System Settings, Privacy & Security, and choose **Open Anyway**. On recent macOS versions, right-click and Open no longer works for unsigned apps.
3. On first launch the Welcome sheet asks where to keep your files. Press **Continue** and choose a folder, or create one (the suggestion is `Silly MIDI Tools` in your Documents folder). The app is sandboxed, so it can only use a folder you have picked. See Working folder.
4. Drop an audio file onto the window, or press Command-O. WAV, MP3, FLAC, M4A, AIFF and anything else Core Audio decodes are supported.
5. Choose a model in the inspector. Basic Pitch is selected for you and works straight away. The other models download on first use (see Models).
6. Press **Transcribe**. The result is saved in your working folder as a MIDI file, and you can open it in the editor.

## Working folder

The app keeps everything in one folder you choose, with two subfolders it creates:

- `Audio/` holds the audio you add.
- `MIDI/` holds every transcription and every edit, saved automatically.

The sidebar lists both folders and updates when files appear or disappear, including changes made in Finder. The folder is remembered across launches with a security-scoped bookmark. If you cancel the folder panel, nothing is chosen and the Welcome sheet stays until you pick a folder.

**Adding audio.** In Settings, General, **When you add audio** decides what happens to a file you open or drop:

- **Copy into the Audio folder** (the default) copies it. The original is not touched.
- **Leave it where it is** keeps a bookmark to the file. If it is later moved or deleted, its sidebar row shows a warning; use the row's context menu, **Relink…**, to point it at the file again, or **Remove from Library**.

**Changing the folder** (Settings, General, **Choose…** or **Reset to Default…**) only changes where the app looks. It does not move or delete any file in the old folder.

## Transcriptions, editing and import

- **Auto-save.** When a run finishes, or when you cancel one that already found notes, the result is written to `MIDI/{audio name}.mid`. The file remembers its source audio and model, so the next run of the same audio replaces it in place.
- **Your edits are never overwritten.** A file you have edited is left alone: a new transcription of the same audio is saved next to it as `{name} 2.mid`. A cancelled run never replaces an earlier complete result, and a file that is not this audio's output is never touched.
- **MIDI editor.** Select a `.mid` file in the sidebar. It has Select, Draw and Erase tools, click, Shift-click and box selection, snapped move and resize, a velocity lane, a snap grid (1/4 to 1/32 note, or off), Quantize, transpose, nudge, and Undo and Redo. Notes live between C1 and B6. Each track can be muted, soloed or hidden without changing a note. The inspector lets you type a note's start, length and velocity, rename the file (the name stays unique in the folder), and draw on a new instrument track picked from **Draw on**. With notes selected, the velocity lane only changes those.
- **Save and unsaved changes.** Command-S saves the file in place and marks it as edited. Switching files, closing the window or quitting asks whether to save, discard or cancel. A save that fails keeps your edits and says why. A save refuses to overwrite a file that changed on disk after you opened it.
- **Import.** **Import MIDI…** (Shift-Command-O) copies a Standard MIDI File (type 0 or 1, with the usual ticks-per-beat timing) into `MIDI/` byte for byte. A file that is not valid MIDI, is damaged, or uses SMPTE or type 2 timing is refused and nothing is written. Notes outside C1 to B6 are skipped and counted.
- **Playback.** Play, Stop and Loop work on both screens, and the position shows time and bar.beat. Space plays and pauses, L toggles Loop, and clicking the ruler moves the playhead. Settings can make the roll follow the playhead.

## Keyboard shortcuts

Help, **Keyboard Shortcuts** (Command-/) lists them all. The main ones:

| Keys | Action |
| --- | --- |
| Command-O, Shift-Command-O | Open audio, import MIDI |
| Command-S | Save the MIDI file |
| Command-E | Export MIDI |
| Command-1, Command-2 | Audio, MIDI editor |
| Option-Command-I | Show or hide the inspector |
| Command-+, Command-- | Zoom |
| Space, L | Play or pause, Loop |
| V, D, E | Select, Draw, Erase (MIDI editor) |
| Up and Down arrows | Transpose by a semitone (Shift: an octave) |
| Left and Right arrows | Nudge by one snap step |
| Option-Left, Option-Right | Previous and next note |
| Q | Quantize the selection, or everything |
| Left and Right on a slice handle | Move it 0.1 s (Shift: 1 s); Home and End go to its limits |

## Features

- **Audio input.** Drop or open a file and see its waveform with a time ruler. Drag the handles to change the slice, drag across empty waveform to pick a new slice, drag inside the slice to move it, and click to move the playhead. A slice is at least 0.5 s long. Exported notes can keep the original timeline or start at zero.
- **Three engines.** MuScriptor (multi-instrument, drums included), Basic Pitch (fast, any pitched audio) and a piano model (high-resolution, piano only). The picker shows each model's licence.
- **Streaming piano roll.** Notes appear while a MuScriptor run is still going, coloured by instrument. Show or hide instruments with the legend. Cancel keeps the notes found so far.
- **Instruments, device and threads.** For MuScriptor you can restrict the transcription to chosen instruments, pick the compute device (Auto, a GPU, or CPU) and set the thread count.
- **Note velocity.** The piano model predicts velocity itself. For MuScriptor, which has none, a toggle (on by default) estimates velocity from the audio's loudness at each onset. Basic Pitch notes use the amplitude it reports.
- **Playback.** Play the notes through the built-in General MIDI sound bank, next to the original audio. Mix between the two with one slider, change the speed from 0.5x to 2x, and loop the slice. Playback needs an audio output device.
- **Key and scale detection.** Ranks major, minor, dorian, phrygian, lydian, mixolydian and locrian in all twelve keys, from the transcribed notes, or from the audio file with the Detect from audio button.
- **MIDI export.** Type 1 Standard MIDI File with one track per instrument. Drag the MIDI chip into Finder or a DAW, or use Export (Command-E). The export sheet can embed the model's licence notice in the file and add the detected key to the file name, for example `Song - Eb minor.mid`.
- **Licences in the app.** The About window lists every third-party component and its licence text.

## Models

| Model | Licence | Download | Use |
| --- | --- | --- | --- |
| MuScriptor small, medium, large (Mirelo and Kyutai; GGUF conversion by Damien Ronssin) | CC BY-NC 4.0 | 0.2 to 2.7 GB | Non-commercial use only |
| Piano (ONNX) (Kong et al., ONNX conversion by LanOss) | CC BY 4.0 | 154 MB | Piano only. Commercial use allowed with credit |
| Basic Pitch (Spotify) | Apache-2.0 | Built in | Commercial use allowed |

Basic Pitch is selected on a fresh install. Pick another model in the inspector and the button reads **Download & Transcribe**; the download happens when you press it, then the run starts. A failed or offline download shows a message with **Try Again**, and nothing is changed.

Downloads are pinned to a fixed revision and checked against a SHA-256 before use. Models are stored in the app's sandbox container under Application Support. Settings, Models shows each model's licence, lets you download or delete it, and can reveal the folder. **Manage Models…** in the model picker opens it.

MuScriptor weights are gated on Hugging Face. The first time you use one, an alert tells you its size and takes you to the licence sheet. You need a Hugging Face account, you must accept the terms on the model page, and you paste a read token (Settings, Hugging Face, or in the sheet) before the download starts. The piano model is not gated.

## Build from source

Requirements: macOS 26 or later, Xcode 26 or later, `xcodegen`, `cmake` and `ninja`.

```sh
git clone --recurse-submodules https://github.com/Sillybit-io/audio-to-midi-app.git
cd audio-to-midi-app
scripts/build-engine.sh
xcodegen generate
xcodebuild -project SillyMIDITools.xcodeproj -scheme SillyMIDITools -destination 'platform=macOS' build CODE_SIGN_IDENTITY=-
```

The Xcode project is generated from `project.yml` and is not checked in, so run `xcodegen generate` after cloning and after editing `project.yml`. Builds are for the host architecture only and are ad-hoc signed.

To run the tests, replace `build` with `test` and keep `CODE_SIGN_IDENTITY=-`, as the CI workflow does: the tests that create real security-scoped bookmarks need the app's entitlements, which an unsigned build (`CODE_SIGNING_ALLOWED=NO`) leaves out. The end-to-end piano tests need the model, which `scripts/fetch-piano-onnx.sh` downloads.

## Releasing

1. Raise `CFBundleShortVersionString` and `CFBundleVersion` in `project.yml`.
2. Write the release notes in `.github/release/notes/<version>.md`. Without that file the release lists commit subjects instead. The install steps and the zip's SHA-256 are added for you.
3. Push to `main` and wait for CI to pass.
4. On GitHub, open Actions, Release, **Run workflow** on `main`. Tick **draft** to review the release before it goes public.

The workflow builds the Apple silicon app on a runner, checks its version, architecture and signature, tags the commit `v<version>`, and attaches `SillyMIDITools-<version>-macOS-arm64.zip` and its `.sha256` to the release. It refuses to run if the version is already tagged or CI hasn't passed on the commit.

## Known limits

- Release builds are Apple silicon only, and are not notarized.
- The piano model handles one instrument; on other music it reports piano notes for whatever it hears.
- Velocity estimated for MuScriptor is relative loudness, not a measurement of how hard a note was played.
- Key detection ranks likely keys; modes that share most of their notes (for example dorian and natural minor) can be close.
- OGG files are not decoded.
- Export and the editor use a fixed 120 bpm, 4/4 grid. Tempo and time signature can't be edited. Importing a file converts its tempo changes into real time, and saving an edited file writes it back at 120 bpm.
- Saving from the editor writes notes, velocities and track instruments only. Pitch bends, controllers such as sustain, and lyrics in a file you edit are not kept.
- Importing type 2 and SMPTE-timed MIDI files is not supported.

## Licence

The app code is licensed under the Apache License 2.0, see `LICENSE`. Third-party components and model licences are listed in `THIRD_PARTY_NOTICES.md`.
