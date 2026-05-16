import SwiftUI

struct PhoneticCellView: View {
    let cell: PhoneticCell
    var segment: ReaderSegment? = nil
    let isShowingIPA: Bool
    let ipaFontSize: Double
    let cellWidth: CGFloat
    var isPopup: Bool = false

//    @EnvironmentObject private var popupModel: PopupModel
    @Environment(PopupModel.self) var popupModel

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
                            .fill(Color.accentColor.opacity(0.1))
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
