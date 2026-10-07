# Onsets and Frames Drums (ONNX)

Drum transcription with velocity, trained on isolated drum audio (the Expanded Groove MIDI Dataset, 444 hours). A conversion
to ONNX of the E-GMD checkpoint of Magenta's
[Onsets and Frames](https://github.com/magenta/magenta/tree/main/magenta/models/onsets_frames_transcription) drums model
(Callender, Hawthorne, Engel). Best on drum-only audio such as an e-kit recording, a drum stem or a loop.

- Input `waveform`: `[1, samples]` float32, mono, 44.1 kHz, values in [-1, 1], at least 2049 samples. The log-mel
  spectrogram (librosa, 250 bands, 100 frames per second) is part of the graph.
- Outputs `onset_probs` and `velocity`: `[1, samples // 441 + 1, 8]` at 100 frames per second for the eight trained pitches
  36, 38, 48, 42, 51, 53, 49, 75 (kick, snare, toms, closed hi-hat, ride, ride bell and cowbell, crash, clave).
- A hit is an onset probability above 0.5; velocity is `int(clip(v, 0, 1) * 127)`.
- Only the onset and velocity branches are kept. Matches the original TensorFlow graph restored from the same checkpoint to
  within 1e-3 (measured 4e-5).

Converted by the [Silly MIDI Tools](https://github.com/Sillybit-io/silly-midi-tools) scripts in `scripts/drums/`.
