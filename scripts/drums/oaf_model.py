"""Onsets and Frames Drums (Callender, Hawthorne, Engel; Magenta, Apache-2.0) as a PyTorch module with its log-mel
frontend baked in.

The weights come from Magenta's E-GMD checkpoint (e-gmd_checkpoint.zip, model.ckpt-569400). Only what the drums-only
model uses is kept: the onset branch (conv stack, FC, bidirectional LSTM, logits) and the velocity branch (conv stack,
FC, linear). The offset and frame heads are unused for drums and left out.

The module takes a mono 44.1 kHz waveform in [-1, 1] and returns, at 100 frames per second, the onset probabilities and
the raw velocity values for the eight pitches the model was trained on (see PITCHES).
"""
import librosa
import numpy as np
import tensorflow as tf
import torch
import torch.nn as nn
import torch.nn.functional as F

SAMPLE_RATE = 44100
HOP = 441
N_FFT = 2048
N_MELS = 250
FMIN = 30.0
TOP_DB = 80.0
MIN_PITCH = 21  # constants.MIN_MIDI_PITCH
# The '8-hit' drum_data_map base pitches: kick, snare, toms, closed hi-hat, ride, ride bell and cowbell, crash, clave.
PITCHES = [36, 38, 48, 42, 51, 53, 49, 75]
COLUMNS = [p - MIN_PITCH for p in PITCHES]


class Frontend(nn.Module):
    """librosa.feature.melspectrogram(n_mels=250, fmin=30, htk=True, hop=441) then librosa.power_to_db, as in data.py."""

    def __init__(self):
        super().__init__()
        self.register_buffer("window", torch.hann_window(N_FFT, periodic=True))
        mel = librosa.filters.mel(sr=SAMPLE_RATE, n_fft=N_FFT, n_mels=N_MELS, fmin=FMIN, htk=True)
        self.register_buffer("mel", torch.from_numpy(mel.T.copy()).float())  # [1025, 250]

    def forward(self, wave):  # wave: [1, N], N > 1024 -> [1, N // 441 + 1, 250]
        padded = F.pad(wave.unsqueeze(1), (N_FFT // 2, N_FFT // 2), mode="reflect").squeeze(1)
        spec = torch.stft(padded, n_fft=N_FFT, hop_length=HOP, win_length=N_FFT, window=self.window,
                          center=False, onesided=True, return_complex=False)  # [1, 1025, frames, 2]
        power = spec[..., 0] ** 2 + spec[..., 1] ** 2
        mel = torch.matmul(power.transpose(1, 2), self.mel)
        db = 10.0 * torch.log10(torch.clamp(mel, min=1e-10))
        return torch.maximum(db, db.max() - TOP_DB)


class ConvStack(nn.Module):
    """magenta conv_net: three 3x3 'SAME' convs (no bias) -> batch norm (no scale) -> ReLU, 2x freq pooling after the
    last two, then the FC layer. Pooling is 'VALID', so 250 -> 125 -> 62 mel columns."""

    def __init__(self):
        super().__init__()
        self.convs = nn.ModuleList(nn.Conv2d(i, o, 3, padding=1, bias=False) for i, o in ((1, 16), (16, 16), (16, 32)))
        self.norms = nn.ModuleList(nn.BatchNorm2d(o, eps=1e-3, affine=True) for o in (16, 16, 32))
        for norm in self.norms:
            norm.weight.requires_grad_(False)  # slim.batch_norm(scale=False): gamma stays 1
        self.fc = nn.Linear(62 * 32, 256)

    def forward(self, spec):  # [1, T, 250]
        x = spec.unsqueeze(1)
        for index, (conv, norm) in enumerate(zip(self.convs, self.norms)):
            x = F.relu(norm(conv(x)))
            if index > 0:
                x = F.max_pool2d(x, (1, 2), (1, 2))
        return F.relu(self.fc(x.permute(0, 2, 3, 1).flatten(2)))  # frequency-major like tf.reshape on [B, T, F, C]


class DrumsOaF(nn.Module):
    def __init__(self):
        super().__init__()
        self.frontend = Frontend()
        self.onset_conv, self.velocity_conv = ConvStack(), ConvStack()
        self.lstm = nn.LSTM(256, 64, batch_first=True, bidirectional=True)
        self.onset_logits = nn.Linear(128, 88)
        self.velocity = nn.Linear(256, 88)
        self.register_buffer("columns", torch.tensor(COLUMNS))

    def head(self, spec):
        hidden, _ = self.lstm(self.onset_conv(spec))
        onsets = torch.sigmoid(self.onset_logits(hidden))
        velocity = self.velocity(self.velocity_conv(spec))
        return onsets.index_select(2, self.columns), velocity.index_select(2, self.columns)

    def forward(self, wave):
        return self.head(self.frontend(wave))


def _lstm_gates(a, hidden=64):
    """TF BasicLSTMCell splits i, j, f, o; PyTorch expects i, f, g(=j), o."""
    i, j, f, o = np.split(a, 4, axis=-1)
    return np.concatenate([i, f, j, o], axis=-1)


def _load_stack(stack, reader, scope):
    def var(path):
        return torch.from_numpy(np.ascontiguousarray(reader.get_tensor(f"{scope}/{path}")))

    for index, (conv, norm) in enumerate(zip(stack.convs, stack.norms)):
        conv.weight.data = var(f"conv{index}/weights").permute(3, 2, 0, 1).contiguous()
        norm.weight.data = torch.ones_like(var(f"conv{index}/BatchNorm/beta"))
        norm.bias.data = var(f"conv{index}/BatchNorm/beta")
        norm.running_mean.data = var(f"conv{index}/BatchNorm/moving_mean")
        norm.running_var.data = var(f"conv{index}/BatchNorm/moving_variance")
    stack.fc.weight.data = var("fc_end/weights").T.contiguous()
    stack.fc.bias.data = var("fc_end/biases")


def load_checkpoint(model, prefix):
    reader = tf.train.load_checkpoint(prefix)
    _load_stack(model.onset_conv, reader, "onsets")
    _load_stack(model.velocity_conv, reader, "velocity")

    cell = "onsets/lstm/stack_bidirectional_rnn/cell_0/bidirectional_rnn/{}/basic_lstm_cell/{}"
    for suffix, direction in (("", "fw"), ("_reverse", "bw")):
        kernel = reader.get_tensor(cell.format(direction, "kernel"))  # [256 + 64, 4 * 64]
        bias = reader.get_tensor(cell.format(direction, "bias")).copy()
        bias_ih = _lstm_gates(bias)
        bias_ih[64:128] += 1.0  # BasicLSTMCell forget_bias, applied inside the cell rather than stored
        getattr(model.lstm, "weight_ih_l0" + suffix).data = torch.from_numpy(_lstm_gates(kernel[:256]).T.copy())
        getattr(model.lstm, "weight_hh_l0" + suffix).data = torch.from_numpy(_lstm_gates(kernel[256:]).T.copy())
        getattr(model.lstm, "bias_ih_l0" + suffix).data = torch.from_numpy(bias_ih)
        getattr(model.lstm, "bias_hh_l0" + suffix).data = torch.zeros(256)

    model.onset_logits.weight.data = torch.from_numpy(reader.get_tensor("onsets/onset_logits/weights").T.copy())
    model.onset_logits.bias.data = torch.from_numpy(reader.get_tensor("onsets/onset_logits/biases"))
    model.velocity.weight.data = torch.from_numpy(reader.get_tensor("velocity/onset_velocities/weights").T.copy())
    model.velocity.bias.data = torch.from_numpy(reader.get_tensor("velocity/onset_velocities/biases"))
    return model.eval()
