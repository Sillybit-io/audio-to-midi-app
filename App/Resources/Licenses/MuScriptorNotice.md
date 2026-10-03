# Attribution and conditions of use

## Original work

**MuScriptor** — a multi-instrument automatic music transcription model by
**Mirelo** and **Kyutai**.

- Weights: <https://huggingface.co/MuScriptor>
- Code: <https://github.com/muscriptor/muscriptor>
- Paper: <https://arxiv.org/abs/2607.08168v1>
- Licence: CC BY-NC 4.0, <https://creativecommons.org/licenses/by-nc/4.0/>

This repository is not affiliated with or endorsed by Mirelo or Kyutai.

## Changes made

The original safetensors weights were converted to GGUF and the bulk weights
cast to float16. No retraining, fine-tuning or pruning; no tensor values altered
beyond that cast. The converter is in
[`muscriptor.cpp`](https://github.com/DamRsn/muscriptor.cpp).

## Upstream conditions of use

Mirelo and Kyutai supplement CC BY-NC 4.0 with the following, reproduced
verbatim from the upstream model cards. It is quoted for information: this
repository imposes no terms of its own, and grants these files under
CC BY-NC 4.0 alone.

> MuScriptor is the result of a research collaboration between Mirelo and Kyutai
> whose purpose is to transcribe audio to MIDI/music sheet. It is provided
> primarily for research purposes under the CC BY-NC 4.0 licence supplemented by
> the below specific conditions of use.
>
> Specific conditions of use: MuScriptor and any generated content by MuScriptor
> are provided as is without any warranty of any kind, including but not limited
> to any warranty of non-infringement. Use of MuScriptor and its output must
> comply with all applicable laws and must not result in, involve, or facilitate
> any illegal or unauthorized activity. Prohibited uses include, without
> limitation, inputting music files and transcribing them to MIDI/music sheet
> without having all the necessary rights, including intellectual property
> rights, under applicable laws. Accordingly, users of MuScriptor undertake and
> warrant to have all the necessary rights, including intellectual property
> rights, in connection with their use of MuScriptor and its output. We disclaim
> all liability for any non-compliant use and users of MuScriptor shall
> indemnify, defend, and hold harmless Mirelo and Kyutai from and against any
> and all claims, damages, losses, liabilities, and expenses (including
> reasonable attorneys' fees) incurred by Mirelo and/or Kyutai arising out of or
> resulting from their failure to comply with the terms of the CC BY-NC 4.0
> licence and/or these specific conditions of use.

The authoritative text is on the upstream model cards. Where this copy and
theirs differ, theirs governs.
