import SwiftUI
import UniformTypeIdentifiers

struct SegmentsReaderView: View {
    @StateObject private var model = SegmentsReaderModel()
    @StateObject private var popupModel = PopupModel()
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
        .environmentObject(popupModel)
        .onChange(of: model.segments) { newValue in
            popupModel.allSegments = newValue
        }
        .onAppear {
            popupModel.allSegments = model.segments
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("SegmentsReader")
                    .font(.title2.weight(.semibold))

                Spacer()

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

    private func presentFilePicker() {
#if os(macOS)
        model.openFile()
#else
        isImporting = true
#endif
    }
}
