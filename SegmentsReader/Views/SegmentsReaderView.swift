import SwiftUI
import UniformTypeIdentifiers

struct SegmentsReaderView: View {
    @State private var model = SegmentsReaderModel()
    @State private var popupModel = PopupModel()
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if model.isNotEmptySegments {
                SegmentScrollView(segments: model.segments)
            } else {
                emptyState
            }
        }
        .padding(18)
        .frame(minWidth: 560, idealWidth: 720, minHeight: 520, idealHeight: 720)
        .overlay {
            CellPopupView()
        }
        .environment(popupModel)
        .environment(model)
        .onChange(of: model.segments) {
            popupModel.allSegments = model.segments
        }
        .onAppear {
            popupModel.allSegments = model.segments
            model.restoreLastURL()
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                model.load(url)
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }

    // MARK: - Header
    //
    // Bindings for settable properties use Bindable(model) — the @Observable
    // equivalent of $model from @StateObject.  playbackSpeed is private(set),
    // so it gets an explicit Binding(get:set:) pointing at the setter method.

    private var header: some View {
        let m = Bindable(model)
        let speedBinding = Binding<Float>(
            get: { model.playbackSpeed },
            set: { model.setPlaybackSpeed($0) }
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("SegmentsReader")
                    .font(.title2.weight(.semibold))

                Spacer()

                if model.isNotEmptySegments {
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Toggle("Loop", isOn: m.isLooping)
                                .toggleStyle(.checkbox)

                            if model.isLooping {
                                Picker("", selection: m.loopGap) {
                                    Text("0.0s gap").tag(TimeInterval(0.0))
                                    Text("0.5s gap").tag(TimeInterval(0.5))
                                    Text("1.0s gap").tag(TimeInterval(1.0))
                                    Text("1.5s gap").tag(TimeInterval(1.5))
                                    Text("2.0s gap").tag(TimeInterval(2.0))
                                    Text("2.5s gap").tag(TimeInterval(2.5))
                                    Text("3.0s gap").tag(TimeInterval(3.0))
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 90)
                            }
                        }

                        HStack(spacing: 2) {
                            Text("Offset")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            TextField(
                                "",
                                value: m.timeOffset,
                                format: .number.precision(.fractionLength(1))
                            )
                            .frame(width: 54)
                            .multilineTextAlignment(.trailing)

                            Text("s")
                                .foregroundStyle(.secondary)

                            Stepper(
                                "",
                                value: m.timeOffset,
                                in: -20...20,
                                step: 0.1
                            )
                            .labelsHidden()
                        }

                        Picker("Speed", selection: speedBinding) {
                            Text("0.5x").tag(Float(0.5))
                            Text("0.75x").tag(Float(0.75))
                            Text("1.0x").tag(Float(1.0))
                            Text("1.25x").tag(Float(1.25))
                            Text("1.5x").tag(Float(1.5))
                            Text("2.0x").tag(Float(2.0))
                        }
                        .pickerStyle(.menu)
                        .frame(width: 110)
                    }
                }

                Button(action: presentFilePicker) {
                    Label("Open", systemImage: "folder")
                }
                .keyboardShortcut("o")
            }

            HStack(spacing: 8) {
                Label(model.statusText, systemImage: model.isNotEmptySegments ? "text.page" : "doc")
                    .font(.caption)
                    .lineLimit(1)

                if let fileName = model.fileURL?.lastPathComponent {
                    Text(fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let errorText = model.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.page.badge.magnifyingglass")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.secondary)

            Button(action: presentFilePicker) {
                Label("Open JSON", systemImage: "folder")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func presentFilePicker() {
#if os(macOS)
        model.openFile()
#else
        isImporting = true
#endif
    }
}
