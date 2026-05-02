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

    func testAudioHintsCanSplitSparseChineseDraftAtPauses() {
        let text = "第一段内容 第二段内容 第三段内容。"
        let context = TextSegmentationContext(
            timedSegments: [],
            audioBoundaryHints: [
                AudioBoundaryHint(time: 2.9, duration: 0.25, confidence: 0.7),
                AudioBoundaryHint(time: 5.9, duration: 0.25, confidence: 0.7)
            ],
            audioDuration: 9
        )

        let segments = TextSegmenter().sentenceSegments(from: text, context: context)

        XCTAssertEqual(segments.map(\.text), [
            "第一段内容",
            "第二段内容",
            "第三段内容。"
        ])
    }

    func testSplitsChineseNewsCopyWithArabicNumbersConservatively() {
        let text = "今天起我国队 53个非洲建交国全面实施零关税举措中国也由此成为全球首个对所有非洲建交国和所有建交的最不发达国家实施单方面全面临关税的主要经济体 。根据中国海关统计 2025年我国与 53个非洲建交国双边贸易总值超 3480亿美元创历史新高 2026年一季度贸易额总值为 921.6亿美元同比增长 26.8%"
        let context = TextSegmentationContext(
            timedSegments: [],
            audioBoundaryHints: [
                audioHint(near: " 53个非洲", in: text),
                audioHint(near: " 2025年", in: text),
                audioHint(near: " 3480亿美元", in: text),
                audioHint(near: " 921.6亿美元", in: text),
                audioHint(near: " 26.8%", in: text)
            ],
            audioDuration: 100
        )

        let segments = TextSegmenter().sentenceSegments(from: text, context: context)

        XCTAssertEqual(segments.map(\.text), [
            "今天起我国队 53个非洲建交国全面实施零关税举措中国也由此成为全球首个对所有非洲建交国和所有建交的最不发达国家实施单方面全面临关税的主要经济体 。",
            "根据中国海关统计 2025年我国与 53个非洲建交国双边贸易总值超 3480亿美元创历史新高",
            "2026年一季度贸易额总值为 921.6亿美元同比增长 26.8%"
        ])
    }

    func testSegmentLocalValueStoresSourceTextByLanguage() throws {
        let zhValue = TextSegmentValue(sourceLang: "zh", sourceText: "这是第一句。")
        let enValue = TextSegmentValue(sourceLang: "en", sourceText: "This is one sentence.")

        XCTAssertEqual(zhValue.zhText, "这是第一句。")
        XCTAssertEqual(zhValue.enText, "")
        XCTAssertEqual(enValue.enText, "This is one sentence.")
        XCTAssertEqual(enValue.zhText, "")

        let encoded = try JSONEncoder().encode([zhValue])
        let decoded = try JSONDecoder().decode([TextSegmentValue].self, from: encoded)
        XCTAssertEqual(decoded, [zhValue])
    }

    private func audioHint(near marker: String, in text: String) -> AudioBoundaryHint {
        guard let markerRange = text.range(of: marker) else {
            return AudioBoundaryHint(time: 0, duration: 0.25, confidence: 0.7)
        }

        let offset = text.distance(from: text.startIndex, to: markerRange.lowerBound)
        let midpoint = Double(offset) / Double(text.count) * 100
        return AudioBoundaryHint(time: midpoint - 0.125, duration: 0.25, confidence: 0.7)
    }
}
