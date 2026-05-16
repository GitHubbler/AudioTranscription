import SwiftUI

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
    .environment(PopupModel())
}
