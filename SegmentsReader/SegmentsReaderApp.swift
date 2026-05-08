#if os(macOS)
import AppKit
#endif
import SwiftUI
import UniformTypeIdentifiers

@main
struct SegmentsReaderApp: App {
    var body: some Scene {
        WindowGroup {
            SegmentsReaderView()
        }
#if os(macOS)
        .windowResizability(.contentSize)
#endif
    }
}

@MainActor
final class SegmentsReaderModel: ObservableObject {
    @Published private(set) var fileURL: URL?
    @Published private(set) var segments: [ReaderSegment] = []
    @Published private(set) var statusText = "Open segmented JSON"
    @Published private(set) var errorText: String?

    var isNotEmptySegments: Bool {
        !segments.isEmpty
    }

    func openFile() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
#endif
    }

    func load(_ url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

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

@MainActor
final class PopupModel: ObservableObject {
    @Published var activeCell: PhoneticCell?
    @Published var activeSegment: ReaderSegment?
    
    @AppStorage("PopupPosition.x") var positionX: Double = 300
    @AppStorage("PopupPosition.y") var positionY: Double = 150
    
    var position: CGPoint {
        get { CGPoint(x: positionX, y: positionY) }
        set {
            positionX = Double(newValue.x)
            positionY = Double(newValue.y)
        }
    }
    
    var allSegments: [ReaderSegment] = []
    var currentGridColumns: Int = 1
    
    func navigate(dx: Int, dy: Int) {
        guard let cell = activeCell, let segment = activeSegment else { return }
        
        let cells = segment.record.phoneticCells
        guard !cells.isEmpty else { return }
        
        var newIndex = cell.index
        
        if dx != 0 {
            newIndex += dx
        }
        if dy != 0 {
            newIndex += dy * max(1, currentGridColumns)
        }
        
        if newIndex >= 0 && newIndex < cells.count {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                activeCell = cells[newIndex]
            }
        } else {
            if newIndex < 0 {
                if let segIndex = allSegments.firstIndex(where: { $0.id == segment.id }), segIndex > 0 {
                    let prevSegment = allSegments[segIndex - 1]
                    let prevCells = prevSegment.record.phoneticCells
                    if !prevCells.isEmpty {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            activeSegment = prevSegment
                            activeCell = prevCells.last
                        }
                    }
                }
            } else {
                if let segIndex = allSegments.firstIndex(where: { $0.id == segment.id }), segIndex < allSegments.count - 1 {
                    let nextSegment = allSegments[segIndex + 1]
                    let nextCells = nextSegment.record.phoneticCells
                    if !nextCells.isEmpty {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            activeSegment = nextSegment
                            activeCell = nextCells.first
                        }
                    }
                }
            }
        }
    }
    
    func navigateToExtreme(isFirst: Bool) {
        guard let segment = activeSegment else { return }
        let cells = segment.record.phoneticCells
        guard !cells.isEmpty else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            activeCell = isFirst ? cells.first : cells.last
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

    @AppStorage("SegmentsReader.ipaFontSize") private var ipaFontSize = 8.0
    @State private var showsPhoneticGrid = false
    @State private var showsIPA = true

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                if showsPhoneticGrid, segment.record.isAbleToShowPhoneticGrid {
                    expandedContent
                } else {
                    normalContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            if segment.record.isAbleToShowPhoneticGrid {
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

        if showsIPA {
            IPAFontSizeControl(fontSize: $ipaFontSize)
        }

        PhoneticScoreView(segment: segment, isShowingIPA: showsIPA, ipaFontSize: ipaFontSize)
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

struct IPAFontSizeControl: View {
    @Binding var fontSize: Double

    var body: some View {
        HStack(spacing: 8) {
            Button {
                fontSize = max(Self.minimumSize, fontSize - 1)
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("Smaller IPA")

            Text("IPA \(Int(fontSize)) pt")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .center)

            Button {
                fontSize = min(Self.maximumSize, fontSize + 1)
            } label: {
                Image(systemName: "textformat.size.larger")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("Larger IPA")
        }
        .controlSize(.small)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private static let minimumSize = 8.0
    private static let maximumSize = 22.0
}

struct PhoneticScoreView: View {
    let segment: ReaderSegment
    let isShowingIPA: Bool
    let ipaFontSize: Double
    
    @EnvironmentObject private var popupModel: PopupModel

    private var cellWidth: CGFloat {
        guard isShowingIPA else { return 58 }
        return min(150, max(58, CGFloat(ipaFontSize) * 6.4 + 18))
    }

    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: cellWidth, maximum: cellWidth + 12), spacing: 5, alignment: .top)
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            ForEach(segment.record.phoneticCells) { cell in
                PhoneticCellView(
                    cell: cell,
                    segment: segment,
                    isShowingIPA: isShowingIPA,
                    ipaFontSize: ipaFontSize,
                    cellWidth: cellWidth
                )
            }
        }
        .padding(.top, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { updateColumns(width: proxy.size.width) }
                    .onChange(of: proxy.size.width) { updateColumns(width: $0) }
            }
        )
    }
    
    private func updateColumns(width: CGFloat) {
        let cols = max(1, Int((width + 5) / (cellWidth + 5)))
        popupModel.currentGridColumns = cols
    }
}

struct PhoneticCellView: View {
    let cell: PhoneticCell
    var segment: ReaderSegment? = nil
    let isShowingIPA: Bool
    let ipaFontSize: Double
    let cellWidth: CGFloat
    var isPopup: Bool = false

    @EnvironmentObject private var popupModel: PopupModel

    var body: some View {
        if isPopup {
            content
        } else {
            content
                .textSelection(.enabled)
        }
    }

    private var isActiveCell: Bool {
        !isPopup && popupModel.activeSegment?.id == segment?.id && popupModel.activeCell?.index == cell.index
    }

    @ViewBuilder
    private var content: some View {
        let base = VStack(spacing: 3) {
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

            if isShowingIPA {
                Text(cell.ipa)
                    .font(.system(size: ipaFontSize, design: .rounded))
                    .foregroundStyle(ipaTextStyle)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.68)
                    .frame(height: max(21, CGFloat(ipaFontSize) * 2.65), alignment: .top)
            }

            Text(cell.english)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.68)
                .frame(minHeight: 31, alignment: .top)
        }
        .frame(width: cellWidth, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isPopup, let segment = segment {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    popupModel.activeSegment = segment
                    popupModel.activeCell = cell
                }
            }
        }
        
        if isActiveCell {
            base
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.background)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
                    .padding(-4)
                )
                .zIndex(1)
        } else {
            base
        }
    }

    private var ipaTextStyle: HierarchicalShapeStyle {
        ipaFontSize > 8 ? .secondary : .tertiary
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

extension SegmentRecord {
    var isAbleToShowPhoneticGrid: Bool {
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

extension ChineseCharacterUnit {
    var displayIPA: String {
        isCharacterIPAUsable ? ipa : MandarinIPAConverter.ipa(fromPinyin: zhLatnPinyin)
    }
}

private extension String {
    var trimmedForDisplay: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

struct CellPopupView: View {
    @EnvironmentObject var popupModel: PopupModel
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        if let cell = popupModel.activeCell {
            ZStack {
                // 1. The Main Popup
                ZStack(alignment: .topTrailing) {
                    PhoneticCellView(
                        cell: cell,
                        isShowingIPA: true,
                        ipaFontSize: 16.0,
                        cellWidth: 100,
                        isPopup: true
                    )
                    .padding(.top, 16)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .background(Color.primary.opacity(0.04))
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
                .scaleEffect(2.0)
                .position(
                    x: popupModel.position.x + dragOffset.width,
                    y: popupModel.position.y + dragOffset.height
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            popupModel.position.x += value.translation.width
                            popupModel.position.y += value.translation.height
                            dragOffset = .zero
                        }
                )
                .onTapGesture {
                    closePopup()
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .background(
                    Group {
                        Button("") { popupModel.navigate(dx: -1, dy: 0) }.keyboardShortcut(.leftArrow, modifiers: [])
                        Button("") { popupModel.navigate(dx: 1, dy: 0) }.keyboardShortcut(.rightArrow, modifiers: [])
                        Button("") { popupModel.navigate(dx: 0, dy: -1) }.keyboardShortcut(.upArrow, modifiers: [])
                        Button("") { popupModel.navigate(dx: 0, dy: 1) }.keyboardShortcut(.downArrow, modifiers: [])
                        Button("") { popupModel.navigateToExtreme(isFirst: true) }.keyboardShortcut(.leftArrow, modifiers: [.command])
                        Button("") { popupModel.navigateToExtreme(isFirst: false) }.keyboardShortcut(.rightArrow, modifiers: [.command])
                    }
                    .opacity(0)
                )
                
                // 2. The Navigation Toolbar
                VStack {
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Button(action: { popupModel.navigateToExtreme(isFirst: true) }) {
                            VStack {
                                Image(systemName: "arrow.backward.to.line")
                                    .font(.system(size: 32))
                                Text("First")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)

                        Button(action: { popupModel.navigate(dx: -1, dy: 0) }) {
                            VStack {
                                Image(systemName: "arrow.left.square.fill")
                                    .font(.system(size: 32))
                                Text("Left")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)

                        Button(action: { popupModel.navigate(dx: 0, dy: -1) }) {
                            VStack {
                                Image(systemName: "arrow.up.square.fill")
                                    .font(.system(size: 32))
                                Text("Up")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)

                        Button(action: { popupModel.navigate(dx: 0, dy: 1) }) {
                            VStack {
                                Image(systemName: "arrow.down.square.fill")
                                    .font(.system(size: 32))
                                Text("Down")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)

                        Button(action: { popupModel.navigate(dx: 1, dy: 0) }) {
                            VStack {
                                Image(systemName: "arrow.right.square.fill")
                                    .font(.system(size: 32))
                                Text("Right")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { popupModel.navigateToExtreme(isFirst: false) }) {
                            VStack {
                                Image(systemName: "arrow.forward.to.line")
                                    .font(.system(size: 32))
                                Text("Last")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Divider()
                            .frame(height: 32)
                            .padding(.horizontal, 4)
                        
                        Button(action: { closePopup() }) {
                            VStack {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 32))
                                Text("Close")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.bottom, 24)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func closePopup() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            popupModel.activeCell = nil
        }
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
    .environmentObject(PopupModel())
}
