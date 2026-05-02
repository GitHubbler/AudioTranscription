import XCTest
@testable import AudioTranscription

final class TextSegmenterTests: XCTestCase {
    func testSplitsChineseSentenceTerminators() {
        let text = "这是第一句。这是第二句！这是第三句？"

        let segments = TextSegmenter().sentenceSegments(from: text)

        XCTAssertEqual(segments.map(\.text), [
            "这是第一句。",
            "这是第二句！",
            "这是第三句？"
        ])
    }

    func testMergesStandaloneChineseFullStopWithPreviousSentence() {
        let text = "这是第一句\n。"

        let segments = TextSegmenter().sentenceSegments(from: text)

        XCTAssertEqual(segments.map(\.text), ["这是第一句。"])
    }

    func testStillSplitsUnsegmentedEnglishText() {
        let text = "This is one sentence. This is another."

        let segments = TextSegmenter().sentenceSegments(from: text)

        XCTAssertEqual(segments.map(\.text), [
            "This is one sentence.",
            "This is another."
        ])
    }

    func testSplitsChineseNewsCopyWithoutInteriorPunctuation() {
        let text = "开展展期五天第三期以美好生活为主题涵盖玩具及孕婴童时尚家用纺织品文具健康休闲五大板块 21个展区展览面积 51.5万平方米本期展会还将推出超过 150场新品首发活动。"

        let segments = TextSegmenter().sentenceSegments(from: text)

        XCTAssertEqual(segments.map(\.text), [
            "开展展期五天第三期以美好生活为主题涵盖玩具及孕婴童时尚家用纺织品文具健康休闲五大板块",
            "21个展区展览面积 51.5万平方米",
            "本期展会还将推出超过 150场新品首发活动。"
        ])
    }
}
