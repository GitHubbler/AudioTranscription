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
    @Published var statusText = "Choose an audio file"
    @Published var transcriptText = ""
    @Published private(set) var sentenceSegments: [TextSegment] = []
    @Published var selectedFileURL: URL?
    @Published var selectedLanguage = TranscriptionLanguage.automatic

    private let engine = AudioTranscriptionEngine()
    private let segmenter = TextSegmenter()
    private var transcriptionTask: Task<Void, Never>?

    var canOpen: Bool {
        state != .transcribing
    }

    var canStart: Bool {
        selectedFileURL != nil && state != .transcribing
    }

    var canSave: Bool {
        !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func openFile() {
        guard canOpen else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        transcriptionTask?.cancel()
        selectedFileURL = url
        setTranscriptText("")
        state = .fileSelected
        statusText = "Ready: \(url.lastPathComponent)"
    }

    func startTranscription() {
        guard canStart, let fileURL = selectedFileURL else { return }

        transcriptionTask?.cancel()
        setTranscriptText("")
        state = .transcribing
        statusText = "Preparing transcription..."

        transcriptionTask = Task {
            do {
                let language = selectedLanguage
                let finalText = try await engine.transcribe(fileURL: fileURL, language: language) { [weak self] event in
                    await self?.handle(event)
                }

                await MainActor.run {
                    self.setTranscriptText(finalText)
                    self.state = .completed
                    self.statusText = "Transcription complete: \(self.sentenceSegments.count) sentences"
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.state = self.selectedFileURL == nil ? .idle : .fileSelected
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
        setTranscriptText(transcriptText)
        statusText = "Segmented \(sentenceSegments.count) sentences"
    }

    private func handle(_ event: TranscriptionEvent) {
        switch event {
        case .status(let message):
            statusText = message
        case .transcript(let text):
            setTranscriptText(text)
        }
    }

    func saveTranscription() {
        guard canSave else { return }
        setTranscriptText(transcriptText)

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

    private func setTranscriptText(_ text: String) {
        sentenceSegments = segmenter.sentenceSegments(from: text)
        transcriptText = segmenter.renderSentenceList(sentenceSegments)
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
                .disabled(!model.canSave || !model.canOpen)

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
