# Hand percussion detector

Part of Silly MIDI Tools, licensed under the Apache License 2.0 like the rest of the app.

It is signal processing, not a trained model, and it has no weights. It finds each stroke of a hand drum such as a darbuka or a doumbek as a peak of the spectral flux, then labels the stroke low or high by how its energy splits between the band below 400 Hz and the band above 1.5 kHz. Low strokes (doum) are written as General MIDI Low Conga, and high strokes (tek, ka) as Open Hi Conga.

No open hand-drum transcription model that allows commercial use was found, so none is used. The method was checked on two solo darbuka recordings, Maksum and Saidi, by Wikimedia Commons contributors, licensed CC BY-SA 4.0 (<https://commons.wikimedia.org/>). The recordings are not part of this app.
