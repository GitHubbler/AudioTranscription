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

    func testChineseNewsCopyWithArabicNumbersKeepsPunctuationLevelSegments() {
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
            "根据中国海关统计 2025年我国与 53个非洲建交国双边贸易总值超 3480亿美元创历史新高 2026年一季度贸易额总值为 921.6亿美元同比增长 26.8%"
        ])
    }

    func testSegmentLocalValueStoresSourceTextByLanguage() throws {
        let zhValue = TextSegmentValue(sourceLang: "zh", sourceText: "这是第一句。")
        let enValue = TextSegmentValue(sourceLang: "en", sourceText: "This is one sentence.")

        XCTAssertEqual(zhValue.zhText, "这是第一句。")
        XCTAssertEqual(zhValue.enText, "")
        XCTAssertEqual(zhValue.deText, "")
        XCTAssertEqual(zhValue.roText, "")
        XCTAssertEqual(zhValue.zhLatnPinyin, "")
        XCTAssertEqual(zhValue.ipa, "")
        XCTAssertEqual(enValue.enText, "This is one sentence.")
        XCTAssertEqual(enValue.zhText, "")

        let encoded = try JSONEncoder().encode([zhValue])
        let decoded = try JSONDecoder().decode([TextSegmentValue].self, from: encoded)
        XCTAssertEqual(decoded, [zhValue])
    }

    func testSegmentLocalValueStoresRomanianAndGermanSourceTextByLanguage() throws {
        let deValue = TextSegmentValue(sourceLang: "de", sourceText: "Das ist ein Satz.")
        let roValue = TextSegmentValue(sourceLang: "ro", sourceText: "Aceasta este o propozitie.")

        XCTAssertEqual(deValue.deText, "Das ist ein Satz.")
        XCTAssertEqual(deValue.enText, "")
        XCTAssertEqual(deValue.zhText, "")
        XCTAssertEqual(deValue.roText, "")
        XCTAssertEqual(deValue.sourceTextForTranslation, "Das ist ein Satz.")

        XCTAssertEqual(roValue.roText, "Aceasta este o propozitie.")
        XCTAssertEqual(roValue.enText, "")
        XCTAssertEqual(roValue.zhText, "")
        XCTAssertEqual(roValue.deText, "")
        XCTAssertEqual(roValue.sourceTextForTranslation, "Aceasta este o propozitie.")
    }

    func testTranscriptionLanguageChoicesIncludeGermanAndRomanian() {
        let languagesByID = Dictionary(uniqueKeysWithValues: TranscriptionLanguage.choices.map { ($0.id, $0) })

        XCTAssertEqual(languagesByID["de-DE"]?.languageCode, "de")
        XCTAssertEqual(languagesByID["ro-RO"]?.name, "Romanian")
        XCTAssertEqual(languagesByID["ro-RO"]?.languageCode, "ro")
    }

    func testSegmentLocalValueEncodesPinyinKeyAndDecodesOlderJSON() throws {
        let value = TextSegmentValue(
            sourceLang: "zh",
            enText: "This is the first sentence.",
            zhText: "这是第一句。",
            zhLatnPinyin: "zhè shì dì yī jù.",
            ipa: "ʈʂɤ̂ ʂɻ̩̂"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode([value])
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertTrue(json.contains("\"IPA\""))
        XCTAssertTrue(json.contains("\"zh-Latn-pinyin\""))

        let olderJSON = """
        [
          {
            "sourceLang": "zh",
            "enText": "This is the first sentence.",
            "zhText": "这是第一句。"
          }
        ]
        """
        let decoded = try JSONDecoder().decode([TextSegmentValue].self, from: Data(olderJSON.utf8))
        XCTAssertEqual(decoded.first?.zhLatnPinyin, "")
        XCTAssertEqual(decoded.first?.ipa, "")
        XCTAssertEqual(decoded.first?.deText, "")
        XCTAssertEqual(decoded.first?.roText, "")
        XCTAssertEqual(decoded.first?.zhLexicalUnits, [])
    }

    func testSegmentLocalValueFillsBlankCounterpart() {
        let zhValue = TextSegmentValue(sourceLang: "zh", sourceText: "这是第一句。")
        let enValue = TextSegmentValue(sourceLang: "en", sourceText: "This is one sentence.")

        XCTAssertEqual(
            zhValue.fillingCounterpart(with: "This is the first sentence."),
            TextSegmentValue(
                sourceLang: "zh",
                enText: "This is the first sentence.",
                zhText: "这是第一句。"
            )
        )
        XCTAssertEqual(
            enValue.fillingCounterpart(with: "这是一个句子。"),
            TextSegmentValue(
                sourceLang: "en",
                enText: "This is one sentence.",
                zhText: "这是一个句子。"
            )
        )
    }

    func testSegmentLocalValueFillsChineseRomanization() {
        let value = TextSegmentValue(
            sourceLang: "en",
            enText: "This is one sentence.",
            zhText: "这是一个句子。"
        )

        let romanized = value.fillingChineseRomanization()

        XCTAssertFalse(romanized.zhLatnPinyin.isEmpty)
        XCTAssertTrue(romanized.zhLatnPinyin.lowercased().contains("zh"))
        XCTAssertFalse(romanized.zhCharacterUnits.isEmpty)
        XCTAssertFalse(romanized.zhLexicalUnits.isEmpty)
    }

    func testSegmentLocalValueFillsTemporaryIPAPlaceholder() {
        let value = TextSegmentValue(sourceLang: "de", sourceText: "Das ist ein Satz.")

        let filled = value.fillingPhonetics()

        XCTAssertEqual(filled.ipa, TemporaryIPAAnnotator.placeholder)
        XCTAssertEqual(filled.zhLatnPinyin, "")
    }

    func testChineseLexicalAnnotationSeparatesArabicNumbersFromHanzi() {
        let units = ChineseLexicalAnnotator.units(from: "53个非洲建交国同比增长 26.8%")

        XCTAssertEqual(units.first?.surface, "53")
        XCTAssertEqual(units.first?.kind, .number)
        XCTAssertEqual(units.first?.zhLatnPinyin, "wǔ shí sān")
        XCTAssertEqual(units.first?.enGloss, "fifty-three")
        XCTAssertEqual(units.dropFirst().first?.surface, "个")
        XCTAssertEqual(units.dropFirst().first?.zhLatnPinyin, "gè")
        XCTAssertTrue(units.contains { $0.surface == "非洲" && $0.zhLatnPinyin == "fēi zhōu" })
        XCTAssertFalse(units.contains { $0.surface.contains("53个") })
    }

    func testChineseRomanizerReadsArabicNumbersAsMandarin() {
        let pinyin = ChineseRomanizer.pinyin(from: "53个非洲建交国")

        XCTAssertTrue(pinyin.contains("wǔ shí sān gè"))
        XCTAssertFalse(pinyin.contains("53 g"))
        XCTAssertFalse(pinyin.contains("53g"))
    }

    func testChineseCharacterAnnotationReadsDigitsSeparatelyAndUsesIndependentGlosses() {
        let units = ChineseCharacterAnnotator.units(from: "今天 53个")

        XCTAssertEqual(units.map(\.surface), ["今", "天", "5", "3", "个"])
        XCTAssertEqual(units.map(\.zhLatnPinyin), ["jīn", "tiān", "wǔ", "sān", "gè"])
        XCTAssertEqual(units.map(\.ipa), Array(repeating: TemporaryIPAAnnotator.placeholder, count: 5))
        XCTAssertEqual(units.map(\.enGloss), ["now", "day", "five", "three", "classifier"])
    }

    func testChineseCharacterAnnotationGlossesCurrentNewsSample() {
        let text = "今天起我国队 53个非洲建交国全面实施零关税举措中国也由此成为全球首个对所有非洲建交国和所有建交的最不发达国家实施单方面全面临关税的主要经济体 。"

        let missingGlosses = ChineseCharacterAnnotator.units(from: text)
            .filter { unit in
                isHanzi(unit.surface) || unit.surface.allSatisfy(\.isNumber)
            }
            .filter { $0.enGloss.isEmpty }
            .map(\.surface)

        XCTAssertEqual(missingGlosses, [])
    }

    func testChineseLexicalUnitsDecodeWhenOptionalFieldsAreOmitted() throws {
        let json = """
        [
          {
            "sourceLang": "zh",
            "enText": "53 African countries",
            "zhText": "53个非洲建交国",
            "zh-Latn-pinyin": "53 gè fēi zhōu jiàn jiāo guó",
            "IPA": "u x",
            "zhLexicalUnits": [
              {
                "kind": "number",
                "surface": "53"
              },
              {
                "kind": "hanzi",
                "surface": "个",
                "IPA": "kɤ̂",
                "zh-Latn-pinyin": "gè"
              }
            ]
          }
        ]
        """

        let decoded = try JSONDecoder().decode([TextSegmentValue].self, from: Data(json.utf8))

        XCTAssertEqual(decoded.first?.zhLexicalUnits.first?.zhLatnPinyin, "")
        XCTAssertEqual(decoded.first?.zhLexicalUnits.first?.ipa, "")
        XCTAssertEqual(decoded.first?.zhLexicalUnits.first?.enGloss, "")
        XCTAssertEqual(decoded.first?.zhLexicalUnits.dropFirst().first?.zhLatnPinyin, "gè")
        XCTAssertEqual(decoded.first?.zhLexicalUnits.dropFirst().first?.ipa, "kɤ̂")
        XCTAssertEqual(decoded.first?.ipa, "u x")
    }

    private func audioHint(near marker: String, in text: String) -> AudioBoundaryHint {
        guard let markerRange = text.range(of: marker) else {
            return AudioBoundaryHint(time: 0, duration: 0.25, confidence: 0.7)
        }

        let offset = text.distance(from: text.startIndex, to: markerRange.lowerBound)
        let midpoint = Double(offset) / Double(text.count) * 100
        return AudioBoundaryHint(time: midpoint - 0.125, duration: 0.25, confidence: 0.7)
    }

    private func isHanzi(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) }
    }
}
