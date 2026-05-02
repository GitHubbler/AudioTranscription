import AVFoundation
import CoreMedia
import Foundation
import Speech

enum TranscriptionEvent: Sendable {
    case status(String)
    case transcript(String)
}

struct TimedTranscriptionSegment: Sendable {
    let start: TimeInterval
    let duration: TimeInterval
    let text: String

    var end: TimeInterval {
        start + duration
    }
}

enum AudioTranscriptionError: LocalizedError {
    case speechRecognitionDenied
    case speechRecognitionRestricted
    case speechRecognizerUnavailable
    case speechTranscriberUnavailable
    case unsupportedLocale
    case unsupportedSpeechAssets
    case speechAssetsUnavailable
    case emptyTranscription

    var errorDescription: String? {
        switch self {
        case .speechRecognitionDenied:
            return "Speech Recognition permission was denied."
        case .speechRecognitionRestricted:
            return "Speech Recognition is restricted on this Mac."
        case .speechRecognizerUnavailable:
            return "Speech Recognition is not available for the current locale."
        case .speechTranscriberUnavailable:
            return "The modern SpeechTranscriber API is not available on this Mac."
        case .unsupportedLocale:
            return "No supported speech transcription locale matches the current language."
        case .unsupportedSpeechAssets:
            return "Speech transcription assets are not supported for the selected locale."
        case .speechAssetsUnavailable:
            return "Speech transcription assets could not be installed."
        case .emptyTranscription:
            return "No speech was recognized in the selected file."
        }
    }
}

struct AudioTranscriptionEngine {
    typealias EventHandler = @Sendable (TranscriptionEvent) async -> Void

    func transcribe(fileURL: URL, eventHandler: @escaping EventHandler) async throws -> String {
        try Task.checkCancellation()
        try await requestSpeechRecognitionAuthorization()

        if #available(macOS 26.0, *) {
            return try await transcribeWithSpeechAnalyzer(fileURL: fileURL, eventHandler: eventHandler)
        } else {
            return try await transcribeWithSFSpeechRecognizer(fileURL: fileURL, eventHandler: eventHandler)
        }
    }

    private func requestSpeechRecognitionAuthorization() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .notDetermined:
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            if status == .authorized {
                return
            }
            if status == .restricted {
                throw AudioTranscriptionError.speechRecognitionRestricted
            }
            throw AudioTranscriptionError.speechRecognitionDenied
        case .denied:
            throw AudioTranscriptionError.speechRecognitionDenied
        case .restricted:
            throw AudioTranscriptionError.speechRecognitionRestricted
        @unknown default:
            throw AudioTranscriptionError.speechRecognizerUnavailable
        }
    }

    @available(macOS 26.0, *)
    private func transcribeWithSpeechAnalyzer(fileURL: URL, eventHandler: @escaping EventHandler) async throws -> String {
        guard SpeechTranscriber.isAvailable else {
            throw AudioTranscriptionError.speechTranscriberUnavailable
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw AudioTranscriptionError.unsupportedLocale
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        let modules: [any SpeechModule] = [transcriber]

        try await prepareAssets(for: modules, eventHandler: eventHandler)
        await eventHandler(.status("Transcribing..."))

        let audioFile = try AVAudioFile(forReading: fileURL)
        let analyzer = SpeechAnalyzer(
            modules: modules,
            options: .init(priority: .userInitiated, modelRetention: .whileInUse)
        )

        let resultsTask = Task {
            try await collectModernResults(from: transcriber, eventHandler: eventHandler)
        }

        do {
            _ = try await analyzer.analyzeSequence(from: audioFile)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let finalText = try await resultsTask.value
            guard !finalText.isEmpty else { throw AudioTranscriptionError.emptyTranscription }
            return finalText
        } catch {
            resultsTask.cancel()
            throw error
        }
    }

    @available(macOS 26.0, *)
    private func prepareAssets(for modules: [any SpeechModule], eventHandler: EventHandler) async throws {
        switch await AssetInventory.status(forModules: modules) {
        case .installed:
            return
        case .unsupported:
            throw AudioTranscriptionError.unsupportedSpeechAssets
        case .downloading:
            await eventHandler(.status("Downloading speech assets..."))
        case .supported:
            await eventHandler(.status("Installing speech assets..."))
        @unknown default:
            throw AudioTranscriptionError.speechAssetsUnavailable
        }

        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            try await request.downloadAndInstall()
        }

        guard await AssetInventory.status(forModules: modules) == .installed else {
            throw AudioTranscriptionError.speechAssetsUnavailable
        }
    }

    @available(macOS 26.0, *)
    private func collectModernResults(
        from transcriber: SpeechTranscriber,
        eventHandler: EventHandler
    ) async throws -> String {
        var finalizedSegments: [TimedTranscriptionSegment] = []
        var volatileSegment: TimedTranscriptionSegment?

        for try await result in transcriber.results {
            try Task.checkCancellation()

            let segment = TimedTranscriptionSegment(result: result)
            guard !segment.text.isEmpty else { continue }

            if result.isFinal {
                upsert(segment, into: &finalizedSegments)
                volatileSegment = nil
            } else {
                volatileSegment = segment
            }

            await eventHandler(.transcript(renderText(finalizedSegments, volatileSegment: volatileSegment)))
        }

        return renderText(finalizedSegments, volatileSegment: nil)
    }

    private func transcribeWithSFSpeechRecognizer(fileURL: URL, eventHandler: @escaping EventHandler) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en_US")),
              recognizer.isAvailable
        else {
            throw AudioTranscriptionError.speechRecognizerUnavailable
        }

        await eventHandler(.status("Transcribing..."))

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            var latestText = ""
            var recognitionTask: SFSpeechRecognitionTask?

            func finish(_ result: Result<String, Error>) {
                guard !didResume else { return }
                didResume = true
                if case .failure = result {
                    recognitionTask?.cancel()
                }
                recognitionTask = nil

                switch result {
                case .success(let text):
                    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedText.isEmpty {
                        continuation.resume(throwing: AudioTranscriptionError.emptyTranscription)
                    } else {
                        continuation.resume(returning: trimmedText)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    latestText = result.bestTranscription.formattedString
                    Task {
                        await eventHandler(.transcript(latestText))
                    }

                    if result.isFinal {
                        finish(.success(latestText))
                    }
                }

                if let error {
                    finish(.failure(error))
                }
            }
        }
    }

    private func upsert(_ segment: TimedTranscriptionSegment, into segments: inout [TimedTranscriptionSegment]) {
        if let index = segments.firstIndex(where: { abs($0.start - segment.start) < 0.01 }) {
            segments[index] = segment
        } else {
            segments.append(segment)
        }
        segments.sort { $0.start < $1.start }
    }

    private func renderText(
        _ finalizedSegments: [TimedTranscriptionSegment],
        volatileSegment: TimedTranscriptionSegment?
    ) -> String {
        var segments = finalizedSegments
        if let volatileSegment {
            segments.append(volatileSegment)
        }
        return segments
            .sorted { $0.start < $1.start }
            .map(\.text)
            .joined(separator: "\n")
    }
}

@available(macOS 26.0, *)
private extension TimedTranscriptionSegment {
    init(result: SpeechTranscriber.Result) {
        let rawText = String(result.text.characters)
        text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        start = result.range.start.safeSeconds
        duration = result.range.duration.safeSeconds
    }
}

private extension CMTime {
    var safeSeconds: TimeInterval {
        guard isValid, seconds.isFinite else { return 0 }
        return seconds
    }
}
