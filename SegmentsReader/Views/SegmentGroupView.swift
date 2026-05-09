import SwiftUI

struct SegmentGroupView: View {
    let segment: ReaderSegment

    @AppStorage("SegmentsReader.ipaFontSize") private var ipaFontSize = 8.0
    @State private var showsPhoneticGrid = false
    @State private var showsIPA = false

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
