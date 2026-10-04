# Attribution and conditions of use

Model: LanOss/mobimml-piano-transcription, revision 7dff58faf160d4c0bf13be48e30e614faecdba72. Verbatim from its model card:

## Attribution (원저작자)

This model is a format conversion of the checkpoint released by the authors of:

> Qiuqiang Kong, Bochen Li, Xuchen Song, Yuan Wan, Yuxuan Wang.
> **"High-resolution Piano Transcription with Pedals by Regressing Onset and Offset Times."**
> IEEE/ACM Transactions on Audio, Speech, and Language Processing, 2021.
> [arXiv:2010.01815](https://arxiv.org/abs/2010.01815)

- Original code: [bytedance/piano_transcription](https://github.com/bytedance/piano_transcription) (Apache 2.0)
- Original checkpoint: [Zenodo record 4034264](https://zenodo.org/record/4034264)
  (`CRNN_note_F1=0.9677_pedal_F1=0.9186.pth`, **CC BY 4.0**)

**Changes made**: the PyTorch checkpoint was exported to ONNX (opset 17, constant folding,
dict outputs flattened to a fixed-order tuple) using
[`tools/export_onnx.py`](https://github.com/Mobi-Lan/MobiMML/blob/main/tools/export_onnx.py).
No weights were modified or fine-tuned.

## License

The model weights are distributed under **CC BY 4.0**, the license of the original checkpoint.
If you redistribute or build upon this file, credit the original authors above.
