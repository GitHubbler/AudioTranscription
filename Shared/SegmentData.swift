import Foundation

typealias SegmentRecord = TextSegmentValue

struct TextSegmentValue: Codable, Equatable, Sendable {
    let sourceLang: String
    let enText: String
    let zhText: String
    let deText: String
    let roText: String
    let zhLatnPinyin: String
    let ipa: String
    let zhCharacterUnits: [ChineseCharacterUnit]
    let zhLexicalUnits: [ChineseLexicalUnit]

    enum CodingKeys: String, CodingKey {
        case sourceLang
        case enText
        case zhText
        case deText
        case roText
        case zhLatnPinyin = "zh-Latn-pinyin"
        case ipa = "IPA"
        case zhCharacterUnits
        case zhLexicalUnits
    }

    init(sourceLang: String = "und", sourceText: String = "") {
        self.sourceLang = sourceLang
        zhLatnPinyin = ""
        ipa = ""
        zhCharacterUnits = []
        zhLexicalUnits = []

        switch sourceLang {
        case "en":
            enText = sourceText
            zhText = ""
            deText = ""
            roText = ""
        case "zh":
            enText = ""
            zhText = sourceText
            deText = ""
            roText = ""
        case "de":
            enText = ""
            zhText = ""
            deText = sourceText
            roText = ""
        case "ro":
            enText = ""
            zhText = ""
            deText = ""
            roText = sourceText
        default:
            enText = ""
            zhText = ""
            deText = ""
            roText = ""
        }
    }

    init(
        sourceLang: String,
        enText: String,
        zhText: String,
        deText: String = "",
        roText: String = "",
        zhLatnPinyin: String = "",
        ipa: String = "",
        zhCharacterUnits: [ChineseCharacterUnit] = [],
        zhLexicalUnits: [ChineseLexicalUnit] = []
    ) {
        self.sourceLang = sourceLang
        self.enText = enText
        self.zhText = zhText
        self.deText = deText
        self.roText = roText
        self.zhLatnPinyin = zhLatnPinyin
        self.ipa = ipa
        self.zhCharacterUnits = zhCharacterUnits
        self.zhLexicalUnits = zhLexicalUnits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceLang = try container.decodeIfPresent(String.self, forKey: .sourceLang) ?? "und"
        enText = try container.decodeIfPresent(String.self, forKey: .enText) ?? ""
        zhText = try container.decodeIfPresent(String.self, forKey: .zhText) ?? ""
        deText = try container.decodeIfPresent(String.self, forKey: .deText) ?? ""
        roText = try container.decodeIfPresent(String.self, forKey: .roText) ?? ""
        zhLatnPinyin = try container.decodeIfPresent(String.self, forKey: .zhLatnPinyin) ?? ""
        ipa = try container.decodeIfPresent(String.self, forKey: .ipa) ?? ""
        zhCharacterUnits = try container.decodeIfPresent([ChineseCharacterUnit].self, forKey: .zhCharacterUnits) ?? []
        zhLexicalUnits = try container.decodeIfPresent([ChineseLexicalUnit].self, forKey: .zhLexicalUnits) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceLang, forKey: .sourceLang)
        try container.encode(enText, forKey: .enText)
        try container.encode(zhText, forKey: .zhText)

        if !deText.isEmpty {
            try container.encode(deText, forKey: .deText)
        }

        if !roText.isEmpty {
            try container.encode(roText, forKey: .roText)
        }

        if !zhLatnPinyin.isEmpty {
            try container.encode(zhLatnPinyin, forKey: .zhLatnPinyin)
        }

        if !ipa.isEmpty {
            try container.encode(ipa, forKey: .ipa)
        }

        if !zhCharacterUnits.isEmpty {
            try container.encode(zhCharacterUnits, forKey: .zhCharacterUnits)
        }

        if !zhLexicalUnits.isEmpty {
            try container.encode(zhLexicalUnits, forKey: .zhLexicalUnits)
        }
    }

    var counterpartLanguageCode: String? {
        switch sourceLang {
        case "en":
            zhText.isEmpty ? "zh" : nil
        case "zh":
            enText.isEmpty ? "en" : nil
        default:
            nil
        }
    }

    var sourceTextForTranslation: String? {
        switch sourceLang {
        case "en":
            enText.isEmpty ? nil : enText
        case "zh":
            zhText.isEmpty ? nil : zhText
        case "de":
            deText.isEmpty ? nil : deText
        case "ro":
            roText.isEmpty ? nil : roText
        default:
            nil
        }
    }

    var phoneticBasisText: String? {
        if !zhText.isEmpty {
            return zhText
        }

        return sourceTextForTranslation
    }

    func fillingCounterpart(with translatedText: String) -> TextSegmentValue {
        switch sourceLang {
        case "en" where zhText.isEmpty:
            copy(zhText: translatedText)
        case "zh" where enText.isEmpty:
            copy(enText: translatedText)
        default:
            self
        }
    }

    func fillingPhonetics() -> TextSegmentValue {
        fillingChineseRomanization().fillingTemporaryIPA()
    }

    func fillingChineseRomanization() -> TextSegmentValue {
        guard !zhText.isEmpty else { return self }

        let lexicalUnits = zhLexicalUnits.isEmpty
            ? ChineseLexicalAnnotator.units(from: zhText)
            : zhLexicalUnits
        let characterUnits = zhCharacterUnits.isEmpty
            ? ChineseCharacterAnnotator.units(from: zhText)
            : zhCharacterUnits
        let pinyin = zhLatnPinyin.isEmpty
            ? ChineseRomanizer.pinyin(from: zhText)
            : zhLatnPinyin

        guard pinyin != zhLatnPinyin
            || characterUnits != zhCharacterUnits
            || lexicalUnits != zhLexicalUnits else {
            return self
        }

        return copy(
            zhLatnPinyin: pinyin,
            zhCharacterUnits: characterUnits,
            zhLexicalUnits: lexicalUnits
        )
    }

    func fillingTemporaryIPA() -> TextSegmentValue {
        guard ipa.isEmpty, let phoneticBasisText else { return self }

        let ipa = TemporaryIPAAnnotator.ipaPlaceholder(for: phoneticBasisText, languageCode: sourceLang)
        guard !ipa.isEmpty else { return self }

        return copy(ipa: ipa)
    }

    func copy(
        enText: String? = nil,
        zhText: String? = nil,
        deText: String? = nil,
        roText: String? = nil,
        zhLatnPinyin: String? = nil,
        ipa: String? = nil,
        zhCharacterUnits: [ChineseCharacterUnit]? = nil,
        zhLexicalUnits: [ChineseLexicalUnit]? = nil
    ) -> TextSegmentValue {
        TextSegmentValue(
            sourceLang: sourceLang,
            enText: enText ?? self.enText,
            zhText: zhText ?? self.zhText,
            deText: deText ?? self.deText,
            roText: roText ?? self.roText,
            zhLatnPinyin: zhLatnPinyin ?? self.zhLatnPinyin,
            ipa: ipa ?? self.ipa,
            zhCharacterUnits: zhCharacterUnits ?? self.zhCharacterUnits,
            zhLexicalUnits: zhLexicalUnits ?? self.zhLexicalUnits
        )
    }
}

struct ChineseCharacterUnit: Codable, Equatable, Sendable {
    let surface: String
    let zhLatnPinyin: String
    let ipa: String
    let enGloss: String

    enum CodingKeys: String, CodingKey {
        case surface
        case zhLatnPinyin = "zh-Latn-pinyin"
        case ipa = "IPA"
        case enGloss
    }

    init(
        surface: String,
        zhLatnPinyin: String = "",
        ipa: String = "",
        enGloss: String = ""
    ) {
        self.surface = surface
        self.zhLatnPinyin = zhLatnPinyin
        self.ipa = ipa
        self.enGloss = enGloss
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        surface = try container.decode(String.self, forKey: .surface)
        zhLatnPinyin = try container.decodeIfPresent(String.self, forKey: .zhLatnPinyin) ?? ""
        ipa = try container.decodeIfPresent(String.self, forKey: .ipa) ?? ""
        enGloss = try container.decodeIfPresent(String.self, forKey: .enGloss) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(surface, forKey: .surface)

        if !zhLatnPinyin.isEmpty {
            try container.encode(zhLatnPinyin, forKey: .zhLatnPinyin)
        }

        if !ipa.isEmpty {
            try container.encode(ipa, forKey: .ipa)
        }

        if !enGloss.isEmpty {
            try container.encode(enGloss, forKey: .enGloss)
        }
    }
}

struct ChineseLexicalUnit: Codable, Equatable, Sendable {
    let surface: String
    let kind: Kind
    let zhLatnPinyin: String
    let ipa: String
    let enGloss: String

    enum Kind: String, Codable, Sendable {
        case hanzi
        case number
        case latin
        case punctuation
        case symbol
    }

    enum CodingKeys: String, CodingKey {
        case surface
        case kind
        case zhLatnPinyin = "zh-Latn-pinyin"
        case ipa = "IPA"
        case enGloss
    }

    init(
        surface: String,
        kind: Kind,
        zhLatnPinyin: String = "",
        ipa: String = "",
        enGloss: String = ""
    ) {
        self.surface = surface
        self.kind = kind
        self.zhLatnPinyin = zhLatnPinyin
        self.ipa = ipa
        self.enGloss = enGloss
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        surface = try container.decode(String.self, forKey: .surface)
        kind = try container.decode(Kind.self, forKey: .kind)
        zhLatnPinyin = try container.decodeIfPresent(String.self, forKey: .zhLatnPinyin) ?? ""
        ipa = try container.decodeIfPresent(String.self, forKey: .ipa) ?? ""
        enGloss = try container.decodeIfPresent(String.self, forKey: .enGloss) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(surface, forKey: .surface)
        try container.encode(kind, forKey: .kind)

        if !zhLatnPinyin.isEmpty {
            try container.encode(zhLatnPinyin, forKey: .zhLatnPinyin)
        }

        if !ipa.isEmpty {
            try container.encode(ipa, forKey: .ipa)
        }

        if !enGloss.isEmpty {
            try container.encode(enGloss, forKey: .enGloss)
        }
    }

    var phoneticDisplayText: String {
        zhLatnPinyin.isEmpty ? surface : zhLatnPinyin
    }
}
