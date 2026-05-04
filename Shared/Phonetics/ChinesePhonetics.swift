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
    static func units(from text: String) -> [ChineseLexicalUnit] {
        var units: [ChineseLexicalUnit] = []
        var current = ""
        var currentKind: ChineseLexicalUnit.Kind?

        func flushCurrent() {
            guard let kind = currentKind, !current.isEmpty else { return }

            if kind == .hanzi {
                units.append(contentsOf: hanziUnits(from: current))
            } else if kind == .number {
                units.append(
                    ChineseLexicalUnit(
                        surface: current,
                        kind: kind,
                        zhLatnPinyin: MandarinNumberRomanizer.pinyinForNumberRun(current),
                        enGloss: TemporaryChineseGlosses.gloss(for: current, kind: kind)
                    )
                )
            } else {
                units.append(
                    ChineseLexicalUnit(
                        surface: current,
                        kind: kind,
                        enGloss: TemporaryChineseGlosses.gloss(for: current, kind: kind)
                    )
                )
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

    private static func hanziUnits(from text: String) -> [ChineseLexicalUnit] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(.simplifiedChinese)

        var units: [ChineseLexicalUnit] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let surface = String(text[range])
            units.append(
                ChineseLexicalUnit(
                    surface: surface,
                    kind: .hanzi,
                    zhLatnPinyin: ChineseRomanizer.pinyinForHanzi(surface),
                    enGloss: TemporaryChineseGlosses.gloss(for: surface, kind: .hanzi)
                )
            )
            return true
        }

        if units.isEmpty {
            units = text.map { character in
                let surface = String(character)
                return ChineseLexicalUnit(
                    surface: surface,
                    kind: .hanzi,
                    zhLatnPinyin: ChineseRomanizer.pinyinForHanzi(surface),
                    enGloss: TemporaryChineseGlosses.gloss(for: surface, kind: .hanzi)
                )
            }
        }

        return units
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
    static func units(from text: String) -> [ChineseCharacterUnit] {
        text.compactMap { character in
            guard !character.isWhitespace else { return nil }

            let surface = String(character)
            let pinyin: String
            if ChineseScriptClassifier.isHanzi(character) {
                pinyin = ChineseRomanizer.pinyinForHanzi(surface)
            } else if character.isNumber {
                pinyin = MandarinNumberRomanizer.pinyinForDigit(character)
            } else {
                pinyin = ""
            }

            return ChineseCharacterUnit(
                surface: surface,
                zhLatnPinyin: pinyin,
                ipa: TemporaryIPAAnnotator.ipaPlaceholder(for: surface, languageCode: "zh"),
                enGloss: TemporaryChineseGlosses.gloss(for: surface, kind: nil)
            )
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

private enum TemporaryChineseGlosses {
    private static let glosses: [String: String] = [
        "今": "now",
        "天": "day",
        "起": "rise/from",
        "我": "I/we",
        "国": "country",
        "队": "team",
        "对": "toward",
        "个": "classifier",
        "非": "not",
        "洲": "continent",
        "非洲": "Africa",
        "建": "build",
        "交": "relations",
        "建交": "establish relations",
        "全": "whole",
        "面": "aspect",
        "实": "actual",
        "施": "carry out",
        "举": "raise",
        "措": "measure",
        "中": "middle",
        "中国": "China",
        "也": "also",
        "由": "from",
        "此": "this",
        "成": "become",
        "为": "be",
        "球": "sphere",
        "全球": "global",
        "首": "first",
        "所": "place",
        "有": "have",
        "所有": "all",
        "和": "and",
        "的": "of",
        "最": "most",
        "不": "not",
        "发": "develop",
        "达": "reach",
        "发达": "developed",
        "家": "home",
        "国家": "country",
        "单": "single",
        "方": "side",
        "临": "face",
        "主要": "main",
        "主": "main",
        "要": "important",
        "经": "manage",
        "济": "aid",
        "体": "body",
        "经济体": "economy",
        "关": "customs/pass",
        "税": "tax",
        "关税": "tariff",
        "零": "zero",
        "全面": "comprehensive",
        "实施": "implement",
        "举措": "measure",
        "根": "root",
        "据": "according",
        "根据": "according to",
        "海": "sea",
        "海关": "customs",
        "统": "unify",
        "计": "count",
        "统计": "statistics",
        "年": "year",
        "与": "with",
        "双": "pair",
        "边": "side",
        "贸": "trade",
        "易": "exchange",
        "贸易": "trade",
        "总": "total",
        "值": "value",
        "总值": "total value",
        "超": "exceed",
        "亿": "hundred million",
        "美": "US",
        "元": "dollar",
        "创": "create",
        "历": "history",
        "史": "history",
        "新": "new",
        "高": "high",
        "一": "one",
        "季": "season",
        "度": "degree",
        "额": "amount",
        "同": "same",
        "比": "compare",
        "增": "increase",
        "长": "grow",
        "增长": "growth"
    ]

    static func gloss(for surface: String, kind: ChineseLexicalUnit.Kind?) -> String {
        if let gloss = glosses[surface] {
            return gloss
        }

        if surface.count == 1, let digitGloss = MandarinNumberRomanizer.englishForDigit(surface) {
            return digitGloss
        }

        if kind == .number {
            return MandarinNumberRomanizer.englishForNumberRun(surface)
        }

        return ""
    }
}

private enum ChineseScriptClassifier {
    static func isHanzi(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) }
    }
}
