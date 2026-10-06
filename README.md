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
5. Choose a model in the inspector on the right (it is open by default; the button at the far right of the toolbar hides it). Basic Pitch is selected for you and works straight away. The other models download on first use (see Models).
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

- **Auto-save and versions.** When a run finishes, or when you cancel one that already found notes, the result is saved as a new version in `MIDI/{audio name} - {model ID}.mid`, for example `song - basic-pitch.mid`. A name that is taken gets a number, as in `song - basic-pitch 2.mid`. The file remembers its source audio, model and version number. Transcribing again, with the same model or another one, never replaces a finished result, so you can compare models side by side.
- **Cancelled runs.** A cancelled run is saved as a partial version. The next run of the same audio and model finishes that file in place, and it keeps its version number. A cancelled run never replaces a finished result: if the same audio and model already have one, the partial notes are not saved.
- **Your edits are never overwritten.** A file you have edited is left alone, and a file that is not this audio's output is never touched.
- **Versions in the sidebar.** The MIDI section groups the transcriptions of each audio file under the audio's name, oldest first, as Version 1, Version 2 and so on. Each row shows the model's name, the note count, and Edited or Partial when either applies. Audio with one transcription shows a single row, a file you renamed keeps your name, and an imported file is a row of its own. Hover over a row to see its file name. Files saved before versions existed keep their names and are numbered in the order they were created.
- **MIDI editor.** Select a `.mid` file in the sidebar. It has Select, Draw and Erase tools, click, Shift-click and box selection, snapped move and resize, a velocity lane, a snap grid (1/4 to 1/32 note, or off), Quantize, transpose, nudge, and Undo and Redo. Notes live between C1 and B6. Each track can be muted, soloed or hidden without changing a note. The inspector lets you type a note's start, length and velocity, rename the file (the name stays unique in the folder), and draw on a new instrument track picked from **Draw on**. With notes selected, the velocity lane only changes those.
- **Save and unsaved changes.** Command-S saves the file in place and marks it as edited. Switching files, closing the window or quitting asks whether to save, discard or cancel. A save that fails keeps your edits and says why. A save refuses to overwrite a file that changed on disk after you opened it.
- **Import.** **Import MIDI…** (Shift-Command-O) copies a Standard MIDI File (type 0 or 1, with the usual ticks-per-beat timing) into `MIDI/` byte for byte. A file that is not valid MIDI, is damaged, or uses SMPTE or type 2 timing is refused and nothing is written. Notes outside C1 to B6 are skipped and counted.
- **Switching files during a run.** A transcription keeps going if you open another file. The sidebar row shows **Transcribing…**, and opening that file again brings back its progress or its result. Only one file is transcribed at a time, so Transcribe on another file waits until it ends.
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
- **MIDI export.** Type 1 Standard MIDI File with one track per instrument. Drag the file from the inspector's Export section into Finder or a DAW, or use Export (Command-E). The export sheet can embed the model's licence notice in the file and add the detected key to the file name, for example `Song - Eb minor.mid`.
- **Licences in the app.** The About window lists every third-party component and its licence text.

## Models

| Model | Licence | Download | Use |
| --- | --- | --- | --- |
| MuScriptor small, medium, large (Mirelo and Kyutai; GGUF conversion by Damien Ronssin) | CC BY-NC 4.0 | 0.2 to 2.7 GB | Non-commercial use only |
| Piano (ONNX) (Kong et al., ONNX conversion by LanOss) | CC BY 4.0 | 154 MB | Piano only. Commercial use allowed with credit |
| Basic Pitch (Spotify) | Apache-2.0 | Built in | Commercial use allowed |

Basic Pitch is selected on a fresh install. Pick another model in the inspector and the button reads **Download & Transcribe**; the download happens when you press it, then the run starts. A failed or offline download shows a message with **Try Again**, and nothing is changed.

Downloads are pinned to a fixed revision and checked against a SHA-256 before use. Models are stored in the app's sandbox container under Application Support. Settings, Models shows each model's licence, lets you download or delete it, and can reveal the folder. **Manage Models…** in the model picker opens it.

MuScriptor weights are gated on Hugging Face. The first time you use one, an alert tells you its size and takes you to the licence sheet. You need a Hugging Face account, you must accept the terms on the model page, and you paste a read token (Settings, Hugging Face, or in the sheet) before the download starts. **Save and check** shows a progress line while it asks Hugging Face, says plainly if the token is rejected (and doesn't keep it) and shows the account when it is accepted. The download button then needs the three statements ticked. The piano model is not gated.

## Troubleshooting

If something goes wrong or the app crashes, turn on **Save debug logs** in Settings, General, Troubleshooting. It takes effect at once, without a relaunch, and stays on until you turn it off.

- Each launch writes one file to `Logs/` in your working folder, for example `Logs/2026-10-06 14.30.12.log`. The newest 10 are kept. **Show Logs in Finder** opens the folder.
- A log starts with the app version, the macOS version and the Mac. Then there is one timestamped line for each thing the app does: opening, dropping and decoding files, each stage of a transcription with the app's memory use, the engine's own output, model downloads, licence checks, playback, and MIDI saves and exports.
- After a crash, the log ends with the reason, for example Swift's `Fatal error: Index out of range` or an uncaught exception, and the stack. The next launch says that the previous session crashed and repeats its last lines.
- macOS still writes its own report to `~/Library/Logs/DiagnosticReports/SillyMIDITools-<date>.ips`. When you report a crash, attach both files.
- Logs name your files and folders. They never contain your Hugging Face token or your audio. Read a log before you post it publicly.

When the switch is off, nothing is written.

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

Debug builds have a **Debug** menu, with **Simulate Crash**, to check that the debug log records each kind of crash. `open SillyMIDITools.app --args -SimulateCrash swift` does the same without the menu; the other kinds are `exception` and `memory`.

To run the tests, replace `build` with `test` and keep `CODE_SIGN_IDENTITY=-`, as the CI workflow does: the tests that create real security-scoped bookmarks need the app's entitlements, which an unsigned build (`CODE_SIGNING_ALLOWED=NO`) leaves out. The end-to-end piano tests need the model, which `scripts/fetch-piano-onnx.sh` downloads.

## Releasing

1. Raise `CFBundleShortVersionString` and `CFBundleVersion` in `project.yml`.
2. Write the release notes in `.github/release/notes/<version>.md`. Without that file the release lists commit subjects instead. The install steps and the zip's SHA-256 are added for you.
3. Push to `main` and wait for CI to pass.
4. On GitHub, open Actions, Release, **Run workflow** on `main`. Tick **draft** to review the release before it goes public.

The workflow builds the Apple silicon app on a runner, checks its version, architecture and signature, tags the commit `v<version>`, and attaches `SillyMIDITools-<version>-macOS-arm64.zip`, its `.sha256` and `SillyMIDITools-<version>-macOS-arm64.dSYM.zip` to the release. It refuses to run if the version is already tagged or CI hasn't passed on the commit.

The dSYM holds the debug symbols of that exact build. To turn an address in a crash stack into a function, file and line, take the app's load address from the **Images** list at the top of the debug log:

```sh
atos -o SillyMIDITools.app.dSYM/Contents/Resources/DWARF/SillyMIDITools -arch arm64 -l <load address> <address>
```

Names already in the stack are mangled Swift; `xcrun swift-demangle` makes them readable.

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
