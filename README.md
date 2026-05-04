# AudioTranscription

A bare-bones macOS app for transcribing audio files into text.

## Current milestone

- Open a user-selected audio or text file.
- Choose a transcription language, or leave it on automatic detection.
- Start transcription from the selected audio file.
- Stream recognized text into the editor as a draft while transcription runs.
- Edit the draft, then segment the current editor text into a structured sentence list.
- Use audio pause hints during segmentation when an audio file is available.
- Save the current transcription as a `.txt` file and a sibling `.json` record file.

## Notes

Open design and data-model ideas live in [docs/Backlog.md](docs/Backlog.md). It is intentionally lightweight: a place to collect and reorder embryos before they deserve heavier process.

The app uses Apple's modern `SpeechAnalyzer` and `SpeechTranscriber` APIs on macOS 26 and newer. On older systems it falls back to `SFSpeechRecognizer` so the proof of concept remains usable while the newer API settles.

Speech transcription is locale-specific. The `Auto` language mode tries the current and preferred system languages first, then a short set of common language-learning locales including English, Simplified Chinese, Traditional Chinese, Japanese, Korean, French, and Spanish.

Sentence segmentation is kept as structured data in the app and rendered as one sentence per line for this proof of concept. Existing newlines are treated as useful boundaries, but sentence detection also works on arbitrary unsegmented prose. When an audio file is selected, the app also derives pause hints from the waveform and uses them as supporting evidence for sentence boundaries.

The JSON output is currently an array of records with `sourceLang`, `enText`, and `zhText`. The source-language field is filled from the detected transcription locale, the selected language, or a filename language suffix such as `.zh.txt`.

macOS will ask for Speech Recognition permission the first time transcription runs.
