import Foundation
import NaturalLanguage

enum ChineseRomanizer {
    static func pinyin(from text: String) -> String {
        ChineseLexicalAnnotator.units(from: text)
            .map(\.phoneticDisplayText)
            .joined(separator: " ")
    }

    fileprivate static func pinyinForHanzi(_ text: String) -> String {
        let mutableText = NSMutableString(string: text)
        guard CFStringTransform(mutableText, nil, kCFStringTransformMandarinLatin, false) else {
            return ""
        }

        return String(mutableText)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

enum ChineseLexicalAnnotator {
    static func units(
        from text: String,
        cache: LocalAnnotationCache? = nil,
        dictionary: ChineseLexicalDictionary = .shared
    ) -> [ChineseLexicalUnit] {
        var units: [ChineseLexicalUnit] = []
        var current = ""
        var currentKind: ChineseLexicalUnit.Kind?

        func flushCurrent() {
            guard let kind = currentKind, !current.isEmpty else { return }

            if kind == .hanzi {
                units.append(contentsOf: hanziUnits(from: current, cache: cache, dictionary: dictionary))
            } else if kind == .number {
                let pinyin = MandarinNumberRomanizer.pinyinForNumberRun(current)
                let unit = ChineseLexicalUnit(
                    surface: current,
                    kind: kind,
                    zhLatnPinyin: pinyin,
                    ipa: MandarinIPAConverter.ipa(fromPinyin: pinyin),
                    enGloss: MandarinNumberRomanizer.englishForNumberRun(current),
                    annotationSource: AnnotationSource.generated.rawValue
                )
                cache?.storeChineseLexicalUnit(unit)
                units.append(unit)
            } else {
                let unit = ChineseLexicalUnit(
                    surface: current,
                    kind: kind,
                    annotationSource: AnnotationSource.generated.rawValue
                )
                cache?.storeChineseLexicalUnit(unit)
                units.append(unit)
            }

            current = ""
            currentKind = nil
        }

        for character in text {
            guard !character.isWhitespace else {
                flushCurrent()
                continue
            }

            let kind = lexicalKind(for: character)
            let continuesNumber = currentKind == .number
                && kind == .punctuation
                && (character == "." || character == "%" || character == ",")

            if let currentKind, currentKind != kind, !continuesNumber {
                flushCurrent()
            }

            current.append(character)
            currentKind = continuesNumber ? .number : kind
        }

        flushCurrent()
        return units
    }

    private static func hanziUnits(
        from text: String,
        cache: LocalAnnotationCache?,
        dictionary: ChineseLexicalDictionary
    ) -> [ChineseLexicalUnit] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(.simplifiedChinese)

        var units: [ChineseLexicalUnit] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let surface = String(text[range])
            units.append(annotatedHanziUnit(surface: surface, cache: cache, dictionary: dictionary))
            return true
        }

        if units.isEmpty {
            units = text.map { character in
                let surface = String(character)
                return annotatedHanziUnit(surface: surface, cache: cache, dictionary: dictionary)
            }
        }

        return units
    }

    private static func annotatedHanziUnit(
        surface: String,
        cache: LocalAnnotationCache?,
        dictionary: ChineseLexicalDictionary
    ) -> ChineseLexicalUnit {
        if let unit = dictionary.lexicalUnit(for: surface, kind: .hanzi) {
            cache?.storeChineseLexicalUnit(unit)
            return unit
        }

        if let cachedUnit = cache?.chineseLexicalUnit(surface: surface, kind: .hanzi) {
            return cachedUnit
        }

        let pinyin = ChineseRomanizer.pinyinForHanzi(surface)
        let unit = ChineseLexicalUnit(
            surface: surface,
            kind: .hanzi,
            zhLatnPinyin: pinyin,
            ipa: MandarinIPAConverter.ipa(fromPinyin: pinyin),
            annotationSource: AnnotationSource.generated.rawValue
        )
        cache?.storeChineseLexicalUnit(unit)
        return unit
    }

    private static func lexicalKind(for character: Character) -> ChineseLexicalUnit.Kind {
        if character.unicodeScalars.allSatisfy({ (0x4E00...0x9FFF).contains($0.value) }) {
            return .hanzi
        }

        if character.isNumber {
            return .number
        }

        if character.isLetter {
            return .latin
        }

        if character.isPunctuation {
            return .punctuation
        }

        return .symbol
    }
}

enum ChineseCharacterAnnotator {
    static func units(
        from text: String,
        cache: LocalAnnotationCache? = nil,
        dictionary: ChineseLexicalDictionary = .shared
    ) -> [ChineseCharacterUnit] {
        text.compactMap { character in
            guard !character.isWhitespace else { return nil }

            let surface = String(character)
            let pinyin: String
            if ChineseScriptClassifier.isHanzi(character) {
                if let unit = dictionary.characterUnit(for: surface) {
                    cache?.storeChineseCharacterUnit(unit)
                    return unit
                }

                pinyin = ChineseRomanizer.pinyinForHanzi(surface)
            } else if character.isNumber {
                pinyin = MandarinNumberRomanizer.pinyinForDigit(character)
            } else {
                pinyin = ""
            }

            if let cachedUnit = cache?.chineseCharacterUnit(surface: surface, pinyin: pinyin) {
                return cachedUnit
            }

            let unit = ChineseCharacterUnit(
                surface: surface,
                zhLatnPinyin: pinyin,
                ipa: MandarinIPAConverter.ipa(fromPinyin: pinyin),
                enGloss: character.isNumber
                    ? MandarinNumberRomanizer.englishForDigit(surface) ?? ""
                    : "",
                annotationSource: AnnotationSource.generated.rawValue
            )
            cache?.storeChineseCharacterUnit(unit)
            return unit
        }
    }
}

private enum MandarinNumberRomanizer {
    private static let digitPinyin: [Character: String] = [
        "0": "líng",
        "1": "yī",
        "2": "èr",
        "3": "sān",
        "4": "sì",
        "5": "wǔ",
        "6": "liù",
        "7": "qī",
        "8": "bā",
        "9": "jiǔ"
    ]

    private static let digitGlosses: [String: String] = [
        "0": "zero",
        "1": "one",
        "2": "two",
        "3": "three",
        "4": "four",
        "5": "five",
        "6": "six",
        "7": "seven",
        "8": "eight",
        "9": "nine"
    ]

    static func pinyinForDigit(_ character: Character) -> String {
        digitPinyin[character] ?? ""
    }

    static func englishForDigit(_ text: String) -> String? {
        digitGlosses[text]
    }

    static func englishForNumberRun(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let hasPercent = trimmed.hasSuffix("%")
        let unsigned = hasPercent ? String(trimmed.dropLast()) : trimmed
        let normalized = unsigned.replacingOccurrences(of: ",", with: "")
        let core: String

        if normalized.contains(".") {
            core = decimalEnglish(normalized)
        } else if let value = Int(normalized), normalized.count <= 4 {
            core = integerEnglish(value)
        } else {
            core = normalized
        }

        guard hasPercent else { return core }
        return [core, "percent"].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func pinyinForNumberRun(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let hasPercent = trimmed.hasSuffix("%")
        let unsigned = hasPercent ? String(trimmed.dropLast()) : trimmed
        let normalized = unsigned.replacingOccurrences(of: ",", with: "")
        let core: String

        if normalized.contains(".") {
            core = decimalPinyin(normalized)
        } else if let value = Int(normalized), normalized.count <= 4 {
            core = integerPinyin(value)
        } else {
            core = digitSequencePinyin(normalized)
        }

        guard hasPercent else { return core }
        return [core, "bǎi fēn hào"].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func decimalPinyin(_ text: String) -> String {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return digitSequencePinyin(text)
        }

        let whole = Int(parts[0]).map(integerPinyin) ?? digitSequencePinyin(String(parts[0]))
        let fractional = digitSequencePinyin(String(parts[1]))
        return [whole, "diǎn", fractional].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func digitSequencePinyin(_ text: String) -> String {
        text.compactMap { digitPinyin[$0] }.joined(separator: " ")
    }

    private static func integerPinyin(_ value: Int) -> String {
        guard value > 0 else { return "líng" }
        guard value < 10_000 else { return digitSequencePinyin(String(value)) }

        let units: [(Int, String)] = [(1000, "qiān"), (100, "bǎi"), (10, "shí")]
        var remainder = value
        var parts: [String] = []
        var needsZero = false

        for (unitValue, unitName) in units {
            let digit = remainder / unitValue
            remainder %= unitValue

            if digit > 0 {
                if needsZero {
                    parts.append("líng")
                    needsZero = false
                }

                if !(unitValue == 10 && digit == 1 && parts.isEmpty) {
                    parts.append(digitPinyin[Character(String(digit))] ?? "")
                }
                parts.append(unitName)
            } else if !parts.isEmpty && remainder > 0 {
                needsZero = true
            }
        }

        if remainder > 0 {
            if needsZero {
                parts.append("líng")
            }
            parts.append(digitPinyin[Character(String(remainder))] ?? "")
        }

        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func decimalEnglish(_ text: String) -> String {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return text }

        let whole = Int(parts[0]).map(integerEnglish) ?? String(parts[0])
        let fractional = parts[1].compactMap { digitGlosses[String($0)] }.joined(separator: " ")
        return [whole, "point", fractional].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func integerEnglish(_ value: Int) -> String {
        let ones = [
            "zero", "one", "two", "three", "four",
            "five", "six", "seven", "eight", "nine"
        ]
        let teens = [
            "ten", "eleven", "twelve", "thirteen", "fourteen",
            "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"
        ]
        let tens = [
            "", "", "twenty", "thirty", "forty",
            "fifty", "sixty", "seventy", "eighty", "ninety"
        ]

        switch value {
        case 0..<10:
            return ones[value]
        case 10..<20:
            return teens[value - 10]
        case 20..<100:
            let ten = value / 10
            let one = value % 10
            return one == 0 ? tens[ten] : "\(tens[ten])-\(ones[one])"
        case 100..<1000:
            let hundred = value / 100
            let rest = value % 100
            return rest == 0
                ? "\(ones[hundred]) hundred"
                : "\(ones[hundred]) hundred \(integerEnglish(rest))"
        case 1000..<10_000:
            let thousand = value / 1000
            let rest = value % 1000
            return rest == 0
                ? "\(ones[thousand]) thousand"
                : "\(ones[thousand]) thousand \(integerEnglish(rest))"
        default:
            return String(value)
        }
    }
}

private enum ChineseScriptClassifier {
    static func isHanzi(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) }
    }
}
