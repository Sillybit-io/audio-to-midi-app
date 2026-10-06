"""The reference Onsets and Frames Drums graph, rebuilt under TF2's compat.v1 so the PyTorch port can be checked.

`conv_net` and the onset / velocity branches of `build_model` are copied from magenta/models/onsets_frames_transcription/
model_tpu.py at the commit pinned in convert-oaf.sh (Apache-2.0, Copyright The Magenta Authors), with the drums
hyperparameters of configs.py. Only the bidirectional LSTM plumbing differs: magenta's `contrib_rnn.stack_bidirectional_
dynamic_rnn` (tf.contrib, gone from TF2) is replaced by `bidirectional_dynamic_rnn` under the same variable scopes, which
gives the checkpoint's variable names unchanged. Nothing here runs at app run time.
"""
import importlib
import sys

import numpy as np

# TensorFlow 2.15 lazily imports tf_keras.legacy_tf_layers for batch norm, but tf_keras 2.15 only ships it under .src.
for _name in ("", ".base", ".core", ".convolutional", ".normalization", ".pooling"):
    sys.modules.setdefault("tf_keras.legacy_tf_layers" + _name,
                           importlib.import_module("tf_keras.src.legacy_tf_layers" + _name))

import tensorflow.compat.v1 as tf  # noqa: E402
import tf_slim as slim  # noqa: E402

HPARAMS = dict(temporal_sizes=[3, 3, 3], freq_sizes=[3, 3, 3], num_filters=[16, 16, 32], pool_sizes=[1, 2, 2],
               dropout_keep_amts=[1.0, 0.25, 0.25], fc_size=256, fc_dropout_keep_amt=0.5, onset_lstm_units=64)
MIDI_PITCHES = 88


def conv_net(inputs, hparams):
    """Builds the ConvNet from Kelz 2016."""
    with slim.arg_scope(
            [slim.conv2d, slim.fully_connected],
            activation_fn=tf.nn.relu,
            weights_initializer=slim.variance_scaling_initializer(factor=2.0, mode="FAN_AVG", uniform=True)):
        net = inputs
        i = 0
        for (conv_temporal_size, conv_freq_size, num_filters, freq_pool_size, dropout_amt) in zip(
                hparams["temporal_sizes"], hparams["freq_sizes"], hparams["num_filters"], hparams["pool_sizes"],
                hparams["dropout_keep_amts"]):
            net = slim.conv2d(net, num_filters, [conv_temporal_size, conv_freq_size], scope="conv" + str(i),
                              normalizer_fn=slim.batch_norm)
            if freq_pool_size > 1:
                net = slim.max_pool2d(net, [1, freq_pool_size], stride=[1, freq_pool_size], scope="pool" + str(i))
            if dropout_amt < 1:
                net = slim.dropout(net, dropout_amt, scope="dropout" + str(i))
            i += 1
        dims = tf.shape(net)
        net = tf.reshape(net, (dims[0], dims[1], net.shape[2] * net.shape[3]), "flatten_end")
        net = slim.fully_connected(net, hparams["fc_size"], scope="fc_end")
        net = slim.dropout(net, hparams["fc_dropout_keep_amt"], scope="dropout_end")
        return net


def bidirectional_lstm(inputs, num_units):
    cell_fw = tf.nn.rnn_cell.BasicLSTMCell(num_units)
    cell_bw = tf.nn.rnn_cell.BasicLSTMCell(num_units)
    with tf.variable_scope("lstm"):
        with tf.variable_scope("stack_bidirectional_rnn"):
            with tf.variable_scope("cell_0"):
                (fw, bw), _ = tf.nn.bidirectional_dynamic_rnn(cell_fw, cell_bw, inputs, dtype=tf.float32,
                                                              parallel_iterations=1)
    return tf.concat([fw, bw], axis=2)


def run(checkpoint_prefix, spec):
    """spec: float32 [T, 250] log-mel frames. Returns (onset_probs, velocity_values), each [T, 88]."""
    graph = tf.Graph()
    with graph.as_default():
        placeholder = tf.placeholder(tf.float32, [1, None, spec.shape[1], 1])
        with slim.arg_scope([slim.batch_norm, slim.dropout], is_training=False):
            with tf.variable_scope("onsets"):
                onset_outputs = bidirectional_lstm(conv_net(placeholder, HPARAMS), HPARAMS["onset_lstm_units"])
                onset_logits = slim.fully_connected(onset_outputs, MIDI_PITCHES, activation_fn=None, scope="onset_logits")
            with tf.variable_scope("velocity"):
                velocity_outputs = conv_net(placeholder, HPARAMS)
                velocity = slim.fully_connected(velocity_outputs, MIDI_PITCHES, activation_fn=None,
                                                scope="onset_velocities")
        onset_probs = tf.sigmoid(onset_logits)
        saver = tf.train.Saver()
        with tf.Session(graph=graph) as session:
            saver.restore(session, checkpoint_prefix)
            probs, values = session.run([onset_probs, velocity], {placeholder: spec[None, :, :, None].astype(np.float32)})
    return probs[0], values[0]
