# Attribution and conditions of use

Model: Onsets and Frames Drums, the E-GMD checkpoint `model.ckpt-569400` from
[magenta/magenta](https://github.com/magenta/magenta) (`onsets_frames_transcription`), commit c15687e.

## Attribution

> Lee Callender, Curtis Hawthorne, Jesse Engel.
> **"Improving Perceptual Quality of Drum Transcription with the Expanded Groove MIDI Dataset."**
> [arXiv:2004.00188](https://arxiv.org/abs/2004.00188), 2020.

> Curtis Hawthorne, Erich Elsen, Jialin Song, Adam Roberts, Ian Simon, Colin Raffel, Jesse Engel, Sageev Oore, Douglas Eck.
> **"Onsets and Frames: Dual-Objective Piano Transcription."** ISMIR 2018. [arXiv:1710.11153](https://arxiv.org/abs/1710.11153)

The model was trained on the Expanded Groove MIDI Dataset (E-GMD), licensed under CC BY 4.0.

## Changes made

The TensorFlow checkpoint was converted to ONNX (opset 17). The onset and velocity branches were re-implemented in
PyTorch with the checkpoint's weights, and the log-mel spectrogram (librosa, 250 bands) was built into the graph. The
offset and frame heads, which the drums-only model does not use, were left out, and only the eight output pitches the
model was trained on are kept. No weights were modified or fine-tuned. The converted file matches the original
TensorFlow graph restored from the same checkpoint to within 1e-3 on the test clip. The conversion scripts are in
`scripts/drums/` of the Silly MIDI Tools repository.

## License

Magenta's code and checkpoint are licensed under the **Apache License, Version 2.0**, Copyright The Magenta Authors.
The licence text is shown under "This app" in Licences.
