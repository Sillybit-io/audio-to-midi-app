# ADTOF Frame_RNN (ONNX)

Automatic drum transcription of full music mixes: bass drum, snare, toms, hi-hat, cymbals and ride. A conversion to ONNX of
the Frame_RNN model of [ADTOF](https://github.com/MZehren/ADTOF) (Zehren, Alunno, Bientinesi), trained on 359 hours of
crowdsourced, non-synthetic music. **Non-commercial use only (CC BY-NC-SA 4.0).**

- Input `waveform`: `[1, samples]` float32, mono, 44.1 kHz, values in [-1, 1]. The log-filtered spectrogram (madmom's, 84
  bands, 100 frames per second) is part of the graph.
- Output `activations`: `[1, ceil(samples / 441), 5]`, sigmoid activations at 100 frames per second for bass drum, snare,
  toms, hi-hat and cymbals with ride.
- Hits come from peak picking per class with the authors' thresholds 0.22, 0.24, 0.32, 0.22, 0.30
  (madmom `NotePeakPickingProcessor`, `pre_avg=0.1, post_avg=0.01, pre_max=0.02, post_max=0.01, combine=0.02`).
- Matches the authors' Keras model fed with madmom features to within 2e-6.

Converted by the [Silly MIDI Tools](https://github.com/Sillybit-io/audio-to-midi-app) scripts in `scripts/drums/`.
