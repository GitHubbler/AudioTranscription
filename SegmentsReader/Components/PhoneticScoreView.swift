import SwiftUI

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
