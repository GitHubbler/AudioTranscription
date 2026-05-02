import AppKit
import SwiftUI
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

    @Published var state: State = .idle
    @Published var statusText = "Choose audio or text"
    @Published var transcriptText = ""
    @Published private(set) var sentenceSegments: [TextSegment] = []
    @Published var selectedFileURL: URL?
    @Published private(set) var selectedAudioURL: URL?
    @Published private(set) var audioBoundaryHints: [AudioBoundaryHint] = []
    @Published var selectedLanguage = TranscriptionLanguage.automatic

    private let engine = AudioTranscriptionEngine()
    private let segmenter = TextSegmenter()
    private let audioHintExtractor = AudioBoundaryHintExtractor()
    private var transcriptionTask: Task<Void, Never>?
    private var audioHintTask: Task<Void, Never>?
    private var segmentationTask: Task<Void, Never>?
    private var audioDuration: TimeInterval?
    private var transcriptionDraft: TranscriptionDraft?

    var canOpen: Bool {
        state != .transcribing
    }

    var canStart: Bool {
        selectedAudioURL != nil && state != .transcribing
    }

    var canSave: Bool {
        !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSegment: Bool {
        canSave && state != .transcribing
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
        selectedFileURL = url
        selectedAudioURL = nil
        transcriptionDraft = nil
        audioBoundaryHints = []
        audioDuration = nil
        sentenceSegments = []

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

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultSaveName

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            try transcriptText.write(to: destinationURL, atomically: true, encoding: .utf8)
            statusText = "Saved \(destinationURL.lastPathComponent)"
        } catch {
            state = .failed
            statusText = error.localizedDescription
        }
    }

    private var defaultSaveName: String {
        guard let selectedFileURL else { return "Transcription.txt" }
        return selectedFileURL.deletingPathExtension().lastPathComponent + ".txt"
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
    }

    private func applySegmentedText(_ text: String) {
        sentenceSegments = segmenter.sentenceSegments(from: text, context: segmentationContext)
        transcriptText = segmenter.renderSentenceList(sentenceSegments)
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

            TextEditor(text: $model.transcriptText)
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
