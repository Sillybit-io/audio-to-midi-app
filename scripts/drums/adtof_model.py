"""ADTOF Frame_RNN (Zehren et al.) as a PyTorch module with madmom's log-filtered spectrogram baked in.

The weights come from the authors' TensorFlow checkpoint (MZehren/ADTOF, CC BY-NC-SA 4.0). The module takes a mono
44.1 kHz waveform in [-1, 1] and returns the five sigmoid activations at 100 frames per second:
BD, SD, TT, HH, CY+RD (GM pitches 35, 38, 47, 42, 49).
"""
import numpy as np
import tensorflow as tf
import torch
import torch.nn as nn
import torch.nn.functional as F

SAMPLE_RATE = 44100
HOP = 441
FRAME = 2048
CHECKPOINT_PREFIX = "layer_with_weights-{}/"


def madmom_filterbank():
    """The 1024 x 84 filterbank madmom builds for the Frame_RNN input (12 bands per octave, 20 Hz to 20 kHz)."""
    import madmom
    from madmom.audio.filters import LogarithmicFilterbank
    fft_freqs = madmom.audio.stft.fft_frequencies(FRAME // 2, SAMPLE_RATE)
    bank = LogarithmicFilterbank(fft_freqs, num_bands=12, fmin=20, fmax=20000, norm_filters=True, unique_filters=True)
    return np.asarray(bank, dtype=np.float32)


class Frontend(nn.Module):
    def __init__(self):
        super().__init__()
        # madmom scales int16 audio by 1/32767 through the window; float input in [-1, 1] is int16 / 32768.
        window = np.hanning(FRAME).astype(np.float32) * (32768.0 / 32767.0)
        self.register_buffer("window", torch.from_numpy(window))
        self.register_buffer("filterbank", torch.from_numpy(madmom_filterbank()))

    def forward(self, wave):  # wave: [1, N] -> [1, N // 441 + 1, 84]; FrameRNN keeps the first ceil(N / 441)
        padded = F.pad(wave, (FRAME // 2, FRAME // 2))
        spec = torch.stft(padded, n_fft=FRAME, hop_length=HOP, win_length=FRAME, window=self.window,
                          center=False, onesided=True, return_complex=False)  # [1, 1025, frames, 2]
        mag = torch.sqrt(spec[..., 0] ** 2 + spec[..., 1] ** 2)[:, : FRAME // 2, :]  # madmom drops the Nyquist bin
        filtered = torch.matmul(mag.transpose(1, 2), self.filterbank)
        return torch.log10(filtered + 1.0)


class FrameRNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.frontend = Frontend()
        sizes = [(1, 32), (32, 32), (32, 64), (64, 64)]
        self.convs = nn.ModuleList(nn.Conv2d(i, o, 3, padding=1) for i, o in sizes)
        self.norms = nn.ModuleList(nn.BatchNorm2d(o, eps=1e-3) for _, o in sizes)
        self.grus = nn.ModuleList(
            nn.GRU(640 if n == 0 else 120, 60, batch_first=True, bidirectional=True) for n in range(3))
        self.dense = nn.Linear(120, 5)

    @staticmethod
    def pool_same(x, width):
        """MaxPool2D((1, 3), padding="same") as TensorFlow does it: the missing columns are split between both edges.
        `width` is the static frequency width (84, then 28); it must not come from a traced shape."""
        total = max((-(-width // 3) - 1) * 3 + 3 - width, 0)
        before = total // 2
        x = F.pad(x, (before, total - before), value=float("-inf"))
        return F.max_pool2d(x, (1, 3), (1, 3))

    def features(self, spec):  # spec: [1, T, 84]
        x = spec.unsqueeze(1)  # [1, 1, T, 84]  (time is H, frequency is W)
        for block, width in enumerate((84, 28)):
            for k in range(2):
                x = self.norms[block * 2 + k](F.relu(self.convs[block * 2 + k](x)))
            x = self.pool_same(x, width)
        return x.permute(0, 2, 3, 1).flatten(2)  # [1, T, 10 * 64], frequency-major like Keras' Reshape

    def head(self, spec):
        x = self.features(spec)
        for gru in self.grus:
            x, _ = gru(x)
        return torch.sigmoid(self.dense(x))

    def forward(self, wave):
        spec = self.frontend(wave)
        # madmom keeps ceil(N / 441) frames; the extra frame would otherwise change what the backward GRU sees.
        return self.head(spec[:, : (wave.shape[1] + HOP - 1) // HOP])


def _gates(a, axis):
    """Keras gate order z, r, h -> PyTorch r, z, n."""
    z, r, h = np.split(a, 3, axis=axis)
    return np.concatenate([r, z, h], axis=axis)


def load_checkpoint(model, prefix):
    reader = tf.train.load_checkpoint(prefix)

    def var(path):
        return torch.from_numpy(np.ascontiguousarray(reader.get_tensor(path + "/.ATTRIBUTES/VARIABLE_VALUE")))

    base = CHECKPOINT_PREFIX.format(0)
    for index, (conv, norm) in enumerate(zip(model.convs, model.norms)):
        conv_path, norm_path = f"{base}layer_with_weights-{index * 2}", f"{base}layer_with_weights-{index * 2 + 1}"
        conv.weight.data = var(conv_path + "/kernel").permute(3, 2, 0, 1).contiguous()
        conv.bias.data = var(conv_path + "/bias")
        norm.weight.data = var(norm_path + "/gamma")
        norm.bias.data = var(norm_path + "/beta")
        norm.running_mean.data = var(norm_path + "/moving_mean")
        norm.running_var.data = var(norm_path + "/moving_variance")
    for index, gru in enumerate(model.grus):
        for suffix, direction in (("", "forward_layer"), ("_reverse", "backward_layer")):
            cell = f"{CHECKPOINT_PREFIX.format(index + 1)}{direction}/cell"
            kernel, recurrent, bias = (var(f"{cell}/{n}").numpy() for n in ("kernel", "recurrent_kernel", "bias"))
            getattr(gru, "weight_ih_l0" + suffix).data = torch.from_numpy(_gates(kernel, 1).T.copy())
            getattr(gru, "weight_hh_l0" + suffix).data = torch.from_numpy(_gates(recurrent, 1).T.copy())
            getattr(gru, "bias_ih_l0" + suffix).data = torch.from_numpy(_gates(bias[0], 0).copy())
            getattr(gru, "bias_hh_l0" + suffix).data = torch.from_numpy(_gates(bias[1], 0).copy())
    model.dense.weight.data = var(CHECKPOINT_PREFIX.format(4) + "kernel").T.contiguous()
    model.dense.bias.data = var(CHECKPOINT_PREFIX.format(4) + "bias")
    return model.eval()
