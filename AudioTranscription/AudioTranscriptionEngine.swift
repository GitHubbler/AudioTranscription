import AVFoundation
import CoreMedia
import Foundation
import Speech

enum TranscriptionEvent: Sendable {
    case status(String)
    case transcript(String)
    case progress(Double)
}

struct TimedTranscriptionSegment: Sendable {
    let start: TimeInterval
    let duration: TimeInterval
    let text: String

    var end: TimeInterval {
        start + duration
    }
}

struct TranscriptionDraft: Sendable {
    let text: String
    let timedSegments: [TimedTranscriptionSegment]
    let localeIdentifier: String?
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
    case noAutomaticLanguageMatch

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
        case .noAutomaticLanguageMatch:
            return "No speech was recognized with the automatic language candidates."
        }
    }
}

struct AudioTranscriptionEngine {
    typealias EventHandler = @Sendable (TranscriptionEvent) async -> Void

    func transcribe(
        fileURL: URL,
        language: TranscriptionLanguage,
        eventHandler: @escaping EventHandler
    ) async throws -> TranscriptionDraft {
        try Task.checkCancellation()
        try await requestSpeechRecognitionAuthorization()

        if #available(macOS 26.0, *) {
            return try await transcribeWithSpeechAnalyzer(
                fileURL: fileURL,
                language: language,
                eventHandler: eventHandler
            )
        } else {
            return try await transcribeWithSFSpeechRecognizer(
                fileURL: fileURL,
                language: language,
                eventHandler: eventHandler
            )
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
    private func transcribeWithSpeechAnalyzer(
        fileURL: URL,
        language: TranscriptionLanguage,
        eventHandler: @escaping EventHandler
    ) async throws -> TranscriptionDraft {
        guard SpeechTranscriber.isAvailable else {
            throw AudioTranscriptionError.speechTranscriberUnavailable
        }

        let candidates = await modernLocaleCandidates(for: language)
        guard !candidates.isEmpty else {
            throw AudioTranscriptionError.unsupportedLocale
        }

        var lastError: Error?
        for locale in candidates {
            do {
                return try await transcribeWithSpeechAnalyzer(
                    fileURL: fileURL,
                    locale: locale,
                    eventHandler: eventHandler
                )
            } catch AudioTranscriptionError.emptyTranscription where language.localeIdentifier == nil {
                lastError = AudioTranscriptionError.emptyTranscription
                await eventHandler(.transcript(""))
            } catch AudioTranscriptionError.unsupportedSpeechAssets where language.localeIdentifier == nil {
                lastError = AudioTranscriptionError.unsupportedSpeechAssets
            } catch AudioTranscriptionError.speechAssetsUnavailable where language.localeIdentifier == nil {
                lastError = AudioTranscriptionError.speechAssetsUnavailable
            } catch {
                throw error
            }
        }

        if let lastError {
            throw lastError
        }
        throw AudioTranscriptionError.noAutomaticLanguageMatch
    }

    @available(macOS 26.0, *)
    private func transcribeWithSpeechAnalyzer(
        fileURL: URL,
        locale: Locale,
        eventHandler: @escaping EventHandler
    ) async throws -> TranscriptionDraft {
        await eventHandler(.status("Trying \(displayName(for: locale))..."))

        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        let modules: [any SpeechModule] = [transcriber]

        try await prepareAssets(for: modules, eventHandler: eventHandler)
        await eventHandler(.status("Transcribing \(displayName(for: locale))..."))

        let audioFile = try AVAudioFile(forReading: fileURL)
        let audioDuration = Double(audioFile.length) / audioFile.fileFormat.sampleRate

        let analyzer = SpeechAnalyzer(
            modules: modules,
            options: .init(priority: .userInitiated, modelRetention: .whileInUse)
        )

        let resultsTask = Task {
            try await collectModernResults(
                from: transcriber,
                audioDuration: audioDuration,
                eventHandler: eventHandler
            )
        }

        do {
            _ = try await analyzer.analyzeSequence(from: audioFile)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let draft = try await resultsTask.value
            guard !draft.text.isEmpty else { throw AudioTranscriptionError.emptyTranscription }
            await eventHandler(.status("Detected \(displayName(for: locale))"))
            await eventHandler(.progress(1.0))
            return TranscriptionDraft(
                text: draft.text,
                timedSegments: draft.timedSegments,
                localeIdentifier: locale.identifier
            )
        } catch is CancellationError {
            resultsTask.cancel()
            let draft = try? await resultsTask.value
            if let draft, !draft.text.isEmpty {
                return TranscriptionDraft(
                    text: draft.text,
                    timedSegments: draft.timedSegments,
                    localeIdentifier: locale.identifier
                )
            }
            throw CancellationError()
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
        audioDuration: TimeInterval,
        eventHandler: EventHandler
    ) async throws -> TranscriptionDraft {
        var finalizedSegments: [TimedTranscriptionSegment] = []
        var volatileSegment: TimedTranscriptionSegment?

        for try await result in transcriber.results {
            if Task.isCancelled { break }

            let segment = TimedTranscriptionSegment(result: result)
            guard !segment.text.isEmpty else { continue }

            if result.isFinal {
                upsert(segment, into: &finalizedSegments)
                volatileSegment = nil
            } else {
                volatileSegment = segment
            }

            await eventHandler(.transcript(renderText(finalizedSegments, volatileSegment: volatileSegment)))
            
            if audioDuration > 0 {
                let currentEnd = result.range.end.safeSeconds
                await eventHandler(.progress(min(1.0, currentEnd / audioDuration)))
            }
        }

        return TranscriptionDraft(
            text: renderText(finalizedSegments, volatileSegment: nil),
            timedSegments: finalizedSegments,
            localeIdentifier: nil
        )
    }

    private func transcribeWithSFSpeechRecognizer(
        fileURL: URL,
        language: TranscriptionLanguage,
        eventHandler: @escaping EventHandler
    ) async throws -> TranscriptionDraft {
        let candidates = legacyLocaleCandidates(for: language)
        guard !candidates.isEmpty else {
            throw AudioTranscriptionError.unsupportedLocale
        }

        var lastError: Error?
        for locale in candidates {
            do {
                return try await transcribeWithSFSpeechRecognizer(
                    fileURL: fileURL,
                    locale: locale,
                    eventHandler: eventHandler
                )
            } catch AudioTranscriptionError.emptyTranscription where language.localeIdentifier == nil {
                lastError = AudioTranscriptionError.emptyTranscription
                await eventHandler(.transcript(""))
            } catch {
                throw error
            }
        }

        if let lastError {
            throw lastError
        }
        throw AudioTranscriptionError.noAutomaticLanguageMatch
    }

    private func transcribeWithSFSpeechRecognizer(
        fileURL: URL,
        locale: Locale,
        eventHandler: @escaping EventHandler
    ) async throws -> TranscriptionDraft {
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable
        else {
            throw AudioTranscriptionError.speechRecognizerUnavailable
        }

        await eventHandler(.status("Trying \(displayName(for: locale))..."))
        await eventHandler(.status("Transcribing \(displayName(for: locale))..."))

        let audioFile = try? AVAudioFile(forReading: fileURL)
        let audioDuration = audioFile.map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0.0

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        actor TaskBox {
            var task: SFSpeechRecognitionTask?
            var isCancelled = false
            func set(_ task: SFSpeechRecognitionTask?) { self.task = task }
            func cancel() {
                isCancelled = true
                task?.cancel()
            }
        }
        let taskBox = TaskBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var didResume = false
                var latestDraft = TranscriptionDraft(text: "", timedSegments: [], localeIdentifier: locale.identifier)

                func finish(_ result: Result<TranscriptionDraft, Error>) {
                    guard !didResume else { return }
                    didResume = true
                    Task { await taskBox.set(nil) }

                    switch result {
                    case .success(let draft):
                        let trimmedText = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedText.isEmpty {
                            continuation.resume(throwing: AudioTranscriptionError.emptyTranscription)
                        } else {
                            Task {
                                await eventHandler(.status("Detected \(displayName(for: locale))"))
                            }
                            continuation.resume(returning: TranscriptionDraft(
                                text: trimmedText,
                                timedSegments: draft.timedSegments,
                                localeIdentifier: locale.identifier
                            ))
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                let task = recognizer.recognitionTask(with: request) { result, error in
                    Task {
                        let cancelled = await taskBox.isCancelled
                        
                        if let result {
                            latestDraft = TranscriptionDraft(result: result)
                            await eventHandler(.transcript(latestDraft.text))

                            if audioDuration > 0, let lastSegment = result.bestTranscription.segments.last {
                                let end = lastSegment.timestamp + lastSegment.duration
                                await eventHandler(.progress(min(1.0, end / audioDuration)))
                            }

                            if result.isFinal || cancelled {
                                finish(.success(latestDraft))
                                return
                            }
                        }

                        if let error {
                            if cancelled && !latestDraft.text.isEmpty {
                                finish(.success(latestDraft))
                            } else {
                                finish(.failure(error))
                            }
                        }
                    }
                }
                Task { await taskBox.set(task) }
            }
        } onCancel: {
            Task { await taskBox.cancel() }
        }
    }

    @available(macOS 26.0, *)
    private func modernLocaleCandidates(for language: TranscriptionLanguage) async -> [Locale] {
        if let locale = language.locale {
            return await matchingModernLocales(for: [locale])
        }

        return await matchingModernLocales(for: automaticCandidateLocales())
    }

    @available(macOS 26.0, *)
    private func matchingModernLocales(for locales: [Locale]) async -> [Locale] {
        var candidates: [Locale] = []
        for locale in locales {
            guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
                continue
            }
            appendUnique(supportedLocale, to: &candidates)
        }
        return candidates
    }

    private func legacyLocaleCandidates(for language: TranscriptionLanguage) -> [Locale] {
        let supportedLocales = SFSpeechRecognizer.supportedLocales()
        let requestedLocales = language.locale.map { [$0] } ?? automaticCandidateLocales()

        return requestedLocales.reduce(into: []) { candidates, locale in
            guard let match = bestMatch(for: locale, in: supportedLocales) else {
                return
            }
            appendUnique(match, to: &candidates)
        }
    }

    private func automaticCandidateLocales() -> [Locale] {
        let preferredLocales = Locale.preferredLanguages.map(Locale.init(identifier:))
        let defaults = [
            Locale.current,
            Locale(identifier: "en_US"),
            Locale(identifier: "zh_Hans"),
            Locale(identifier: "zh_CN"),
            Locale(identifier: "zh_Hant"),
            Locale(identifier: "zh_TW"),
            Locale(identifier: "ja_JP"),
            Locale(identifier: "ko_KR"),
            Locale(identifier: "fr_FR"),
            Locale(identifier: "es_ES")
        ]

        return (preferredLocales + defaults).reduce(into: []) { locales, locale in
            appendUnique(locale, to: &locales)
        }
    }

    private func bestMatch(for requestedLocale: Locale, in supportedLocales: Set<Locale>) -> Locale? {
        let sortedLocales = supportedLocales.sorted { $0.identifier < $1.identifier }
        let requestedIdentifier = normalizedIdentifier(requestedLocale.identifier)

        if let exactMatch = sortedLocales.first(where: { normalizedIdentifier($0.identifier) == requestedIdentifier }) {
            return exactMatch
        }

        guard let requestedLanguage = requestedIdentifier.split(separator: "_").first else {
            return nil
        }

        if requestedLanguage == "zh" {
            let wantsTraditional = requestedIdentifier.contains("hant") || requestedIdentifier.contains("_tw") || requestedIdentifier.contains("_hk")
            let preferredMarkers = wantsTraditional ? ["hant", "_tw", "_hk", "_mo"] : ["hans", "_cn", "_sg"]

            if let regionalMatch = sortedLocales.first(where: { locale in
                let identifier = normalizedIdentifier(locale.identifier)
                return identifier.hasPrefix("zh") && preferredMarkers.contains(where: identifier.contains)
            }) {
                return regionalMatch
            }
        }

        return sortedLocales.first { locale in
            normalizedIdentifier(locale.identifier).split(separator: "_").first == requestedLanguage
        }
    }

    private func appendUnique(_ locale: Locale, to locales: inout [Locale]) {
        let identifier = normalizedIdentifier(locale.identifier)
        guard !locales.contains(where: { normalizedIdentifier($0.identifier) == identifier }) else {
            return
        }
        locales.append(locale)
    }

    private func normalizedIdentifier(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "-", with: "_").lowercased()
    }

    private func displayName(for locale: Locale) -> String {
        let identifier = locale.identifier
        return Locale.current.localizedString(forIdentifier: identifier) ?? identifier
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
            .joined(separator: " ")
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

private extension TranscriptionDraft {
    init(result: SFSpeechRecognitionResult) {
        text = result.bestTranscription.formattedString
        timedSegments = result.bestTranscription.segments.map { TimedTranscriptionSegment(segment: $0) }
        localeIdentifier = nil
    }
}

private extension TimedTranscriptionSegment {
    init(segment: SFTranscriptionSegment) {
        start = segment.timestamp
        duration = segment.duration
        text = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
