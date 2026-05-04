import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct SegmentsReaderApp: App {
    var body: some Scene {
        WindowGroup {
            SegmentsReaderView()
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class SegmentsReaderModel: ObservableObject {
    @Published private(set) var fileURL: URL?
    @Published private(set) var segments: [ReaderSegment] = []
    @Published private(set) var statusText = "Open segmented JSON"
    @Published private(set) var errorText: String?

    var hasSegments: Bool {
        !segments.isEmpty
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    private func load(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let records = try JSONDecoder().decode([SegmentRecord].self, from: data)
            fileURL = url
            segments = records.enumerated().map { index, record in
                ReaderSegment(number: index + 1, record: record)
            }
            errorText = nil
            statusText = "Loaded \(segments.count) segments"
        } catch {
            errorText = error.localizedDescription
            statusText = "Could not load JSON"
        }
    }
}

struct ReaderSegment: Identifiable, Equatable {
    let number: Int
    let record: SegmentRecord

    var id: Int { number }
}

struct SegmentsReaderView: View {
    @StateObject private var model = SegmentsReaderModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if model.hasSegments {
                SegmentScrollView(segments: model.segments)
            } else {
                emptyState
            }
        }
        .padding(18)
        .frame(minWidth: 560, idealWidth: 720, minHeight: 520, idealHeight: 720)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("SegmentsReader")
                    .font(.title2.weight(.semibold))

                Spacer()

                Button(action: model.openFile) {
                    Label("Open", systemImage: "folder")
                }
                .keyboardShortcut("o")
            }

            HStack(spacing: 8) {
                Label(model.statusText, systemImage: model.hasSegments ? "text.page" : "doc")
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

            Button(action: model.openFile) {
                Label("Open JSON", systemImage: "folder")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SegmentScrollView: View {
    let segments: [ReaderSegment]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(segments) { segment in
                    SegmentGroupView(segment: segment)
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 12)
        }
        .scrollIndicators(.visible)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

struct SegmentGroupView: View {
    let segment: ReaderSegment

    @State private var showsPhoneticGrid = false
    @State private var showsIPA = true

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                if showsPhoneticGrid, segment.record.canShowPhoneticGrid {
                    expandedContent
                } else {
                    normalContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            if segment.record.canShowPhoneticGrid {
                VStack(spacing: 8) {
                    Button {
                        showsPhoneticGrid.toggle()
                    } label: {
                        Image(systemName: showsPhoneticGrid ? "eye.slash" : "eye")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(showsPhoneticGrid ? "Show simple text" : "Show character study grid")

                    if showsPhoneticGrid {
                        Button {
                            showsIPA.toggle()
                        } label: {
                            Image(systemName: showsIPA ? "eye.slash" : "eye")
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(showsIPA ? "Hide IPA" : "Show IPA")
                    }
                }
            }
        }
        .padding(.leading, 18)
        .overlay(alignment: .topLeading) {
            Text("\(segment.number)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 14, alignment: .trailing)
                .padding(.top, 2)
        }
    }

    private var normalContent: some View {
        ForEach(lines) { line in
            Text(line.text)
                .font(line.font)
                .foregroundStyle(line.color)
                .textSelection(.enabled)
                .lineSpacing(line.lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if segment.record.sourceLang == "en", !segment.record.enText.trimmedForDisplay.isEmpty {
            Text(segment.record.enText.trimmedForDisplay)
                .font(SegmentLine.Role.source.font)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        PhoneticScoreView(record: segment.record, showsIPA: showsIPA)
    }

    private var lines: [SegmentLine] {
        SegmentLine.lines(for: segment.record)
    }
}

struct SegmentLine: Identifiable {
    enum Role: Hashable {
        case source
        case sourcePhonetics
        case translation
        case translationPhonetics
    }

    let role: Role
    let text: String

    var id: Role { role }

    var font: Font { role.font }

    var color: HierarchicalShapeStyle {
        switch role {
        case .source:
            return .primary
        case .sourcePhonetics:
            return .secondary
        case .translation:
            return .primary
        case .translationPhonetics:
            return .secondary
        }
    }

    var lineSpacing: CGFloat {
        role == .source ? 3 : 2
    }

    static func lines(for record: SegmentRecord) -> [SegmentLine] {
        switch record.sourceLang {
        case "zh":
            return [
                line(.source, record.zhText),
                line(.sourcePhonetics, record.zhLatnPinyin),
                line(.translation, record.enText)
            ].compactMap { $0 }
        case "en":
            return [
                line(.source, record.enText),
                line(.translation, record.zhText),
                line(.translationPhonetics, record.zhLatnPinyin)
            ].compactMap { $0 }
        case "de":
            return [
                line(.source, record.deText),
                line(.translation, record.zhText),
                line(.translationPhonetics, record.zhLatnPinyin)
            ].compactMap { $0 }
        case "ro":
            return [
                line(.source, record.roText),
                line(.translation, record.zhText),
                line(.translationPhonetics, record.zhLatnPinyin)
            ].compactMap { $0 }
        default:
            return [
                line(.source, record.zhText),
                line(.sourcePhonetics, record.zhLatnPinyin),
                line(.translation, record.enText)
            ].compactMap { $0 }
        }
    }

    private static func line(_ role: Role, _ text: String) -> SegmentLine? {
        let trimmed = text.trimmedForDisplay
        guard !trimmed.isEmpty else { return nil }
        return SegmentLine(role: role, text: trimmed)
    }
}

private extension SegmentLine.Role {
    var font: Font {
        switch self {
        case .source:
            return .system(.title3, design: .default).weight(.semibold)
        case .sourcePhonetics:
            return .system(.body, design: .rounded)
        case .translation:
            return .system(.body, design: .default)
        case .translationPhonetics:
            return .system(.callout, design: .rounded)
        }
    }
}

struct PhoneticScoreView: View {
    let record: SegmentRecord
    let showsIPA: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 50, maximum: 68), spacing: 5, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            ForEach(record.phoneticCells) { cell in
                PhoneticCellView(cell: cell, showsIPA: showsIPA)
            }
        }
        .padding(.top, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PhoneticCellView: View {
    let cell: PhoneticCell
    let showsIPA: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(cell.hanzi)
                .font(.system(size: 23, weight: .semibold))
                .frame(height: 27, alignment: .center)

            Text(cell.pinyin)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)
                .frame(height: 25, alignment: .top)

            if showsIPA {
                Text(cell.ipa)
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.68)
                    .frame(height: 21, alignment: .top)
            }

            Text(cell.english)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.68)
                .frame(minHeight: 31, alignment: .top)
        }
        .frame(width: 58, alignment: .top)
        .textSelection(.enabled)
    }
}

struct PhoneticCell: Identifiable, Equatable {
    let index: Int
    let hanzi: String
    let pinyin: String
    let ipa: String
    let english: String

    var id: Int { index }
}

private extension SegmentRecord {
    var canShowPhoneticGrid: Bool {
        !zhText.trimmedForDisplay.isEmpty && !phoneticCells.isEmpty
    }

    var phoneticCells: [PhoneticCell] {
        let characterUnits = zhCharacterUnits.isEmpty
            ? ChineseCharacterAnnotator.units(from: zhText)
            : zhCharacterUnits

        if !characterUnits.isEmpty {
            return characterUnits.enumerated().map { index, unit in
                PhoneticCell(
                    index: index,
                    hanzi: unit.surface,
                    pinyin: unit.zhLatnPinyin,
                    ipa: unit.displayIPA,
                    english: unit.enGloss
                )
            }
        }

        let characters = zhText
            .filter { !$0.isWhitespace }
            .map(String.init)

        guard !characters.isEmpty else { return [] }

        return characters.enumerated().map { index, character in
            PhoneticCell(
                index: index,
                hanzi: character,
                pinyin: "",
                ipa: TemporaryIPAAnnotator.ipaPlaceholder(for: character, languageCode: "zh"),
                english: ""
            )
        }
    }
}

private extension ChineseCharacterUnit {
    var displayIPA: String {
        hasUsableCharacterIPA ? ipa : MandarinIPAConverter.ipa(fromPinyin: zhLatnPinyin)
    }
}

private extension String {
    var trimmedForDisplay: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

#Preview {
    SegmentScrollView(segments: [
        ReaderSegment(
            number: 1,
            record: SegmentRecord(
                sourceLang: "zh",
                enText: "Starting today, China implements zero-tariff measures for 53 African countries with diplomatic relations.",
                zhText: "今天起我国对 53 个非洲建交国全面实施零关税举措。",
                zhLatnPinyin: "jīn tiān qǐ wǒ guó duì wǔ shí sān gè fēi zhōu jiàn jiāo guó quán miàn shí shī líng guān shuì jǔ cuò."
            )
        ),
        ReaderSegment(
            number: 2,
            record: SegmentRecord(
                sourceLang: "en",
                enText: "Bilateral trade reached a new historical high.",
                zhText: "双边贸易创历史新高。",
                zhLatnPinyin: "shuāng biān mào yì chuàng lì shǐ xīn gāo."
            )
        )
    ])
    .padding()
}
