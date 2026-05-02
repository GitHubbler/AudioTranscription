# AudioTranscription

A bare-bones macOS app for transcribing audio files into text.

## Current milestone

- Open a user-selected audio file.
- Choose a transcription language, or leave it on automatic detection.
- Start transcription from the selected file.
- Stream recognized text into the window while transcription runs.
- Save the current transcription as a `.txt` file.

## Notes

The app uses Apple's modern `SpeechAnalyzer` and `SpeechTranscriber` APIs on macOS 26 and newer. On older systems it falls back to `SFSpeechRecognizer` so the proof of concept remains usable while the newer API settles.

Speech transcription is locale-specific. The `Auto` language mode tries the current and preferred system languages first, then a short set of common language-learning locales including English, Simplified Chinese, Traditional Chinese, Japanese, Korean, French, and Spanish.

macOS will ask for Speech Recognition permission the first time transcription runs.
