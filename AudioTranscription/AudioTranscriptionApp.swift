import AppKit
import SwiftUI
import Translation
import UniformTypeIdentifiers

@main
struct AudioTranscriptionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class TranscriptionModel: ObservableObject {
    enum State {
        case idle
        case fileSelected
        case transcribing
        case completed
        case failed
    }

    enum EditorMode: String, CaseIterable, Identifiable {
        case text = "Text"
        case json = "JSON"

        var id: String { rawValue }
    }

    @Published var state: State = .idle
    @Published var statusText = "Choose audio or text"
    @Published var transcriptText = ""
    @Published var jsonText = ""
    @Published var editorMode = EditorMode.text
    @Published private(set) var sentenceSegments: [TextSegment] = []
    @Published var selectedFileURL: URL?
    @Published private(set) var selectedAudioURL: URL?
    @Published private(set) var audioBoundaryHints: [AudioBoundaryHint] = []
    @Published var selectedLanguage = TranscriptionLanguage.automatic
    @Published var translationConfiguration: TranslationSession.Configuration?
    @Published private(set) var isTranslating = false

    private let engine = AudioTranscriptionEngine()
    private let segmenter = TextSegmenter()
    private let audioHintExtractor = AudioBoundaryHintExtractor()
    private var transcriptionTask: Task<Void, Never>?
    private var audioHintTask: Task<Void, Never>?
    private var segmentationTask: Task<Void, Never>?
    private var audioDuration: TimeInterval?
    private var transcriptionDraft: TranscriptionDraft?
    private var lastJSONSaveURL: URL?
    private var pendingTranslation: PendingTranslation?

    var canOpen: Bool {
        state != .transcribing
    }

    var canStart: Bool {
        selectedAudioURL != nil && state != .transcribing
    }

    var canSave: Bool {
        switch editorMode {
        case .text:
            !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .json:
            !jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var canSegment: Bool {
        !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && state != .transcribing
            && editorMode == .text
    }

    var canTranslate: Bool {
        !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && state != .transcribing
            && !isTranslating
    }

    func openFile() {
        guard canOpen else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        transcriptionTask?.cancel()
        audioHintTask?.cancel()
        segmentationTask?.cancel()
        cancelPendingTranslation()
        selectedFileURL = url
        selectedAudioURL = nil
        transcriptionDraft = nil
        audioBoundaryHints = []
        audioDuration = nil
        sentenceSegments = []
        jsonText = ""
        editorMode = .text
        lastJSONSaveURL = nil

        if isAudioFile(url) {
            selectedAudioURL = url
            setDraftText("")
            state = .fileSelected
            statusText = "Ready: \(url.lastPathComponent)"
            startAudioHintExtraction(for: url)
        } else {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                setDraftText(text)
                state = .completed
                statusText = "Loaded text: \(url.lastPathComponent)"
            } catch {
                state = .failed
                statusText = error.localizedDescription
            }
        }
    }

    func startTranscription() {
        guard canStart, let fileURL = selectedAudioURL else { return }

        transcriptionTask?.cancel()
        setDraftText("")
        transcriptionDraft = nil
        state = .transcribing
        statusText = "Preparing transcription..."

        transcriptionTask = Task {
            do {
                let language = selectedLanguage
                let draft = try await engine.transcribe(fileURL: fileURL, language: language) { [weak self] event in
                    await self?.handle(event)
                }

                await MainActor.run {
                    self.transcriptionDraft = draft
                    self.setDraftText(draft.text)
                    self.state = .completed
                    self.statusText = self.draftReadyStatus
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.state = self.selectedAudioURL == nil ? .idle : .fileSelected
                    self.statusText = "Transcription cancelled"
                }
            } catch {
                await MainActor.run {
                    self.state = .failed
                    self.statusText = error.localizedDescription
                }
            }
        }
    }

    func segmentCurrentText() {
        guard canSegment else { return }

        segmentationTask?.cancel()
        let text = transcriptText
        statusText = selectedAudioURL == nil ? "Segmenting text..." : "Segmenting with audio hints..."

        segmentationTask = Task { [weak self] in
            guard let self else { return }
            await self.ensureAudioHintsIfNeeded()
            await MainActor.run {
                self.applySegmentedText(text)
                self.statusText = "Segmented \(self.sentenceSegments.count) sentences\(self.audioHintSummary)"
            }
        }
    }

    private func handle(_ event: TranscriptionEvent) {
        switch event {
        case .status(let message):
            statusText = message
        case .transcript(let text):
            setDraftText(text)
        }
    }

    func saveTranscription() {
        guard canSave else { return }

        switch editorMode {
        case .text:
            saveTextDraft()
        case .json:
            saveJSONDraft()
        }
    }

    private func saveTextDraft() {
        guard canSave else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultSaveName

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            let records = segmentRecordsForCurrentText()
            let jsonURL = destinationURL.deletingPathExtension().appendingPathExtension("json")

            try transcriptText.write(to: destinationURL, atomically: true, encoding: .utf8)
            try writeSegmentRecords(records, to: jsonURL)
            jsonText = try renderSegmentRecords(records)
            lastJSONSaveURL = jsonURL
            statusText = "Saved \(destinationURL.lastPathComponent) and \(jsonURL.lastPathComponent)"
        } catch {
            state = .failed
            statusText = error.localizedDescription
        }
    }

    private func saveJSONDraft() {
        guard canSave else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultJSONSaveName

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            try validateSegmentJSON(jsonText)
            try jsonText.write(to: destinationURL, atomically: true, encoding: .utf8)
            lastJSONSaveURL = destinationURL
            statusText = "Saved \(destinationURL.lastPathComponent)"
        } catch {
            state = .failed
            statusText = error.localizedDescription
        }
    }

    func translateCurrentSegments() {
        guard canTranslate else { return }

        guard let pair = currentTranslationPair else {
            statusText = "Translation is available for English and Chinese source text"
            return
        }

        let records = segmentRecordsForCurrentText()
        let requestCount = records.filter { $0.counterpartLanguageCode == pair.targetCode }.count
        guard requestCount > 0 else {
            statusText = "No blank \(pair.targetCode) fields to translate"
            return
        }

        pendingTranslation = PendingTranslation(
            records: records,
            sourceCode: pair.sourceCode,
            targetCode: pair.targetCode
        )
        isTranslating = true
        state = .completed
        statusText = "Translating \(requestCount) segments..."
        translationConfiguration = TranslationSession.Configuration(
            source: pair.sourceLanguage,
            target: pair.targetLanguage
        )
    }

    func translatePendingSegments(using session: TranslationSession) async {
        guard let pendingTranslation else { return }

        do {
            var updatedRecords = pendingTranslation.records
            let requests: [TranslationSession.Request] = pendingTranslation.records.enumerated().compactMap { index, record in
                guard record.counterpartLanguageCode == pendingTranslation.targetCode,
                      let text = record.sourceTextForTranslation else {
                    return nil
                }

                return TranslationSession.Request(
                    sourceText: text,
                    clientIdentifier: String(index)
                )
            }

            try await session.prepareTranslation()
            let responses = try await session.translations(from: requests)

            for response in responses {
                guard let identifier = response.clientIdentifier,
                      let index = Int(identifier),
                      updatedRecords.indices.contains(index) else {
                    continue
                }

                updatedRecords[index] = updatedRecords[index].fillingCounterpart(
                    with: response.targetText
                )
            }

            updatedRecords = updatedRecords.map { $0.fillingChineseRomanization() }
            jsonText = try renderSegmentRecords(updatedRecords)
            editorMode = .json
            statusText = "Translated \(responses.count) segments into editable JSON"
        } catch is CancellationError {
            statusText = "Translation cancelled"
        } catch {
            state = .failed
            statusText = error.localizedDescription
        }

        cancelPendingTranslation()
    }

    private var defaultSaveName: String {
        guard let selectedFileURL else { return "Transcription.txt" }
        return selectedFileURL.deletingPathExtension().lastPathComponent + ".txt"
    }

    private var defaultJSONSaveName: String {
        if let lastJSONSaveURL {
            return lastJSONSaveURL.lastPathComponent
        }

        guard let selectedFileURL else { return "Transcription.json" }
        return selectedFileURL.deletingPathExtension().lastPathComponent + ".json"
    }

    private var draftReadyStatus: String {
        "Transcription draft ready\(audioHintSummary)"
    }

    private var audioHintSummary: String {
        audioBoundaryHints.isEmpty ? "" : " (\(audioBoundaryHints.count) audio hints)"
    }

    private var segmentationContext: TextSegmentationContext {
        TextSegmentationContext(
            timedSegments: transcriptionDraft?.timedSegments ?? [],
            audioBoundaryHints: audioBoundaryHints,
            audioDuration: audioDuration
        )
    }

    private func setDraftText(_ text: String) {
        transcriptText = text
        sentenceSegments = []
        editorMode = .text
    }

    private func applySegmentedText(_ text: String) {
        sentenceSegments = localizedSegments(from: text)
        transcriptText = segmenter.renderSentenceList(sentenceSegments)
        editorMode = .text
    }

    private func localizedSegments(from text: String) -> [TextSegment] {
        let sourceLang = currentSourceLanguageCode
        return segmenter
            .sentenceSegments(from: text, context: segmentationContext)
            .map { $0.withSourceLanguage(sourceLang) }
    }

    private func segmentRecordsForCurrentText() -> [TextSegmentValue] {
        localizedSegments(from: transcriptText).map(\.localValue)
    }

    private func writeSegmentRecords(_ records: [TextSegmentValue], to url: URL) throws {
        let data = try encodedSegmentRecords(records)
        try data.write(to: url, options: .atomic)
    }

    private func renderSegmentRecords(_ records: [TextSegmentValue]) throws -> String {
        let data = try encodedSegmentRecords(records)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }

        return text
    }

    private func encodedSegmentRecords(_ records: [TextSegmentValue]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(records)
    }

    private func validateSegmentJSON(_ text: String) throws {
        let data = Data(text.utf8)
        _ = try JSONDecoder().decode([TextSegmentValue].self, from: data)
    }

    private var currentSourceLanguageCode: String {
        if let localeIdentifier = transcriptionDraft?.localeIdentifier,
           let languageCode = localeIdentifier.normalizedLanguageCode {
            return languageCode
        }

        if let languageCode = selectedLanguage.languageCode {
            return languageCode
        }

        if let languageCode = selectedFileURL?.deletingPathExtension().pathExtension.normalizedLanguageCode,
           !languageCode.isEmpty {
            return languageCode
        }

        return "und"
    }

    private var currentTranslationPair: TranslationPair? {
        switch currentSourceLanguageCode {
        case "en":
            TranslationPair(sourceCode: "en", targetCode: "zh")
        case "zh":
            TranslationPair(sourceCode: "zh", targetCode: "en")
        default:
            nil
        }
    }

    private func cancelPendingTranslation() {
        pendingTranslation = nil
        translationConfiguration = nil
        isTranslating = false
    }

    private func isAudioFile(_ url: URL) -> Bool {
        let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        if resourceType?.conforms(to: .audio) == true {
            return true
        }

        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true
    }

    private func startAudioHintExtraction(for url: URL) {
        audioHintTask?.cancel()
        audioHintTask = Task { [weak self] in
            guard let self else { return }
            await self.extractAudioHints(for: url, shouldUpdateStatus: true)
        }
    }

    private func ensureAudioHintsIfNeeded() async {
        if let audioHintTask {
            await audioHintTask.value
            return
        }

        guard let selectedAudioURL, audioDuration == nil else { return }
        await extractAudioHints(for: selectedAudioURL, shouldUpdateStatus: false)
    }

    private func extractAudioHints(for url: URL, shouldUpdateStatus: Bool) async {
        do {
            let extractor = audioHintExtractor
            let analysis = try await Task.detached(priority: .userInitiated) {
                try extractor.analyze(fileURL: url)
            }.value

            guard selectedAudioURL == url else { return }
            audioDuration = analysis.duration
            audioBoundaryHints = analysis.hints
            audioHintTask = nil

            if shouldUpdateStatus, state != .transcribing {
                statusText = state == .completed && !transcriptText.isEmpty
                    ? draftReadyStatus
                    : "Ready: \(url.lastPathComponent)\(audioHintSummary)"
            }
        } catch is CancellationError {
            audioHintTask = nil
        } catch {
            guard selectedAudioURL == url else { return }
            audioHintTask = nil
            audioDuration = nil
            audioBoundaryHints = []
            if shouldUpdateStatus, state != .transcribing {
                statusText = "Ready: \(url.lastPathComponent) (audio hints unavailable)"
            }
        }
    }
}

private struct PendingTranslation {
    let records: [TextSegmentValue]
    let sourceCode: String
    let targetCode: String
}

private struct TranslationPair {
    let sourceCode: String
    let targetCode: String

    var sourceLanguage: Locale.Language {
        Locale.Language(identifier: sourceCode)
    }

    var targetLanguage: Locale.Language {
        Locale.Language(identifier: targetCode)
    }
}

struct ContentView: View {
    @StateObject private var model = TranscriptionModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("AudioTranscription")
                    .font(.title2.weight(.semibold))

                Spacer()

                statusChip
            }

            if let fileName = model.selectedFileURL?.lastPathComponent {
                Label(fileName, systemImage: "waveform")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Picker("Language", selection: $model.selectedLanguage) {
                ForEach(TranscriptionLanguage.choices) { language in
                    Text(language.name).tag(language)
                }
            }
            .pickerStyle(.menu)
            .disabled(!model.canOpen)

            Picker("Editor", selection: $model.editorMode) {
                ForEach(TranscriptionModel.EditorMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.state == .transcribing)

            TextEditor(text: editorTextBinding)
                .font(.system(.body, design: .monospaced))
                .frame(height: 260)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                }

            HStack(spacing: 10) {
                Button(action: model.openFile) {
                    Label("Open", systemImage: "folder")
                }
                .disabled(!model.canOpen)
                .keyboardShortcut("o")

                Button(action: model.startTranscription) {
                    Label("Start", systemImage: "play.fill")
                }
                .disabled(!model.canStart)
                .keyboardShortcut(.return)

                Button(action: model.segmentCurrentText) {
                    Label("Segment", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .disabled(!model.canSegment)

                Button(action: model.translateCurrentSegments) {
                    Label("Translate", systemImage: "translate")
                }
                .disabled(!model.canTranslate)

                Spacer()

                Button(action: model.saveTranscription) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(!model.canSave)
                .keyboardShortcut("s")
            }
        }
        .padding(20)
        .frame(width: 640)
        .translationTask(model.translationConfiguration) { session in
            await model.translatePendingSegments(using: session)
        }
    }

    private var editorTextBinding: Binding<String> {
        Binding(
            get: {
                switch model.editorMode {
                case .text:
                    model.transcriptText
                case .json:
                    model.jsonText
                }
            },
            set: { newValue in
                switch model.editorMode {
                case .text:
                    model.transcriptText = newValue
                case .json:
                    model.jsonText = newValue
                }
            }
        )
    }

    private var statusChip: some View {
        Label(model.statusText, systemImage: statusIcon)
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusIcon: String {
        switch model.state {
        case .idle:
            return "circle"
        case .fileSelected:
            return "doc"
        case .transcribing:
            return "waveform"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }
}
