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
}
