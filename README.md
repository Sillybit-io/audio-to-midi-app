# Silly MIDI Tools

A native macOS app that turns audio into MIDI. Drop an audio file, pick a model and instruments, watch notes appear on a piano roll, play them back, and export a Standard MIDI File.

## Models

| Model | Licence | Use |
| --- | --- | --- |
| MuScriptor small, medium, large (Mirelo and Kyutai; GGUF conversion by Damien Ronssin) | CC BY-NC 4.0 | Non-commercial use only |
| Basic Pitch (Spotify) | Apache-2.0 | Commercial use allowed |

MuScriptor weights are gated on Hugging Face. You need a Hugging Face account, you must accept the terms on the model page, and you paste a read token into Settings before the first download. Models are stored in the app's sandbox container under Application Support, and the picker can reveal or delete them.

## Build

Requirements: macOS 15 or later, Xcode 26, `xcodegen`, `cmake` and `ninja`.

```sh
git clone --recurse-submodules https://github.com/Sillybit-io/audio-to-midi-app.git
cd audio-to-midi-app
scripts/build-engine.sh
xcodegen generate
xcodebuild -project SillyMIDITools.xcodeproj -scheme SillyMIDITools -destination 'platform=macOS' build CODE_SIGN_IDENTITY=-
```

Builds are for the host architecture only and are ad-hoc signed. A downloaded CI build is quarantined by Gatekeeper; right-click and choose Open, or clear the quarantine attribute with `xattr`.

## Known limits

- MuScriptor does not produce note velocity; exports use a fixed default.
- OGG files are not decoded.
- Export uses a fixed 120 bpm, 4/4 grid.

## Licence

The app code is licensed under the Apache License 2.0, see `LICENSE`. Third-party components and model licences are listed in `THIRD_PARTY_NOTICES.md`.
