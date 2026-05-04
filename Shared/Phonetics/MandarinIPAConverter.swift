import Foundation

enum MandarinIPAConverter {
    static func ipa(fromPinyin pinyin: String) -> String {
        pinyin
            .split(whereSeparator: \.isWhitespace)
            .map { ipaForSyllable(String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func ipaForSyllable(_ syllable: String) -> String {
        let normalized = normalizedSyllable(syllable)
        guard !normalized.text.isEmpty else { return "" }

        let parsed = parseInitialAndFinal(normalized.text)
        guard !parsed.final.isEmpty else { return "" }

        let initialIPA = initialMap[parsed.initial] ?? ""
        let finalIPA = ipaFinal(parsed.final, after: parsed.initial)
        guard !finalIPA.isEmpty else { return "" }

        return initialIPA + finalIPA + toneLetter(for: normalized.tone)
    }

    private static func normalizedSyllable(_ syllable: String) -> (text: String, tone: Int) {
        var tone = 5
        var text = ""

        for character in syllable.lowercased() {
            if let replacement = toneMarkedVowels[character] {
                text += replacement.base
                tone = replacement.tone
            } else if character.isLetter || character == "ü" {
                text.append(character)
            }
        }

        return (text.replacingOccurrences(of: "u:", with: "ü"), tone)
    }

    private static func parseInitialAndFinal(_ syllable: String) -> (initial: String, final: String) {
        if syllable.hasPrefix("y") {
            return ("", normalizeYInitial(syllable))
        }

        if syllable.hasPrefix("w") {
            return ("", normalizeWInitial(syllable))
        }

        let initial = initialCandidates.first { syllable.hasPrefix($0) } ?? ""
        var final = String(syllable.dropFirst(initial.count))

        if ["j", "q", "x"].contains(initial), final.hasPrefix("u") {
            final = "ü" + String(final.dropFirst())
        }

        return (initial, final)
    }

    private static func normalizeYInitial(_ syllable: String) -> String {
        switch syllable {
        case "yi": return "i"
        case "yin": return "in"
        case "ying": return "ing"
        case "yu": return "ü"
        case "yue": return "üe"
        case "yuan": return "üan"
        case "yun": return "ün"
        case "you": return "iu"
        default:
            return syllable.hasPrefix("y")
                ? "i" + String(syllable.dropFirst())
                : syllable
        }
    }

    private static func normalizeWInitial(_ syllable: String) -> String {
        switch syllable {
        case "wu": return "u"
        case "wo": return "uo"
        case "wei": return "ui"
        case "wen": return "un"
        default:
            return syllable.hasPrefix("w")
                ? "u" + String(syllable.dropFirst())
                : syllable
        }
    }

    private static func ipaFinal(_ final: String, after initial: String) -> String {
        if final == "i" {
            if ["zh", "ch", "sh", "r"].contains(initial) {
                return "ɻ̩"
            }

            if ["z", "c", "s"].contains(initial) {
                return "ɹ̩"
            }
        }

        return finalMap[final] ?? ""
    }

    private static func toneLetter(for tone: Int) -> String {
        switch tone {
        case 1: return "˥"
        case 2: return "˧˥"
        case 3: return "˨˩˦"
        case 4: return "˥˩"
        default: return "˧"
        }
    }

    private static let initialCandidates = [
        "zh", "ch", "sh",
        "b", "p", "m", "f",
        "d", "t", "n", "l",
        "g", "k", "h",
        "j", "q", "x",
        "r", "z", "c", "s"
    ]

    private static let initialMap: [String: String] = [
        "b": "p",
        "p": "pʰ",
        "m": "m",
        "f": "f",
        "d": "t",
        "t": "tʰ",
        "n": "n",
        "l": "l",
        "g": "k",
        "k": "kʰ",
        "h": "x",
        "j": "tɕ",
        "q": "tɕʰ",
        "x": "ɕ",
        "zh": "ʈʂ",
        "ch": "ʈʂʰ",
        "sh": "ʂ",
        "r": "ʐ",
        "z": "ts",
        "c": "tsʰ",
        "s": "s"
    ]

    private static let finalMap: [String: String] = [
        "a": "a",
        "ai": "aɪ",
        "an": "an",
        "ang": "ɑŋ",
        "ao": "ɑʊ",
        "e": "ɤ",
        "ei": "eɪ",
        "en": "ən",
        "eng": "əŋ",
        "er": "ɑɻ",
        "ê": "ɛ",
        "i": "i",
        "ia": "ja",
        "ian": "jɛn",
        "iang": "jɑŋ",
        "iao": "jaʊ",
        "ie": "jɛ",
        "in": "in",
        "ing": "iŋ",
        "iong": "jʊŋ",
        "iu": "joʊ",
        "o": "ɔ",
        "ong": "ʊŋ",
        "ou": "oʊ",
        "u": "u",
        "ua": "wa",
        "uai": "waɪ",
        "uan": "wan",
        "uang": "wɑŋ",
        "ue": "wɛ",
        "ui": "weɪ",
        "un": "wən",
        "uo": "wɔ",
        "ü": "y",
        "üan": "ɥɛn",
        "üe": "ɥɛ",
        "ün": "yn"
    ]

    private static let toneMarkedVowels: [Character: (base: String, tone: Int)] = [
        "ā": ("a", 1), "á": ("a", 2), "ǎ": ("a", 3), "à": ("a", 4),
        "ē": ("e", 1), "é": ("e", 2), "ě": ("e", 3), "è": ("e", 4),
        "ī": ("i", 1), "í": ("i", 2), "ǐ": ("i", 3), "ì": ("i", 4),
        "ō": ("o", 1), "ó": ("o", 2), "ǒ": ("o", 3), "ò": ("o", 4),
        "ū": ("u", 1), "ú": ("u", 2), "ǔ": ("u", 3), "ù": ("u", 4),
        "ǖ": ("ü", 1), "ǘ": ("ü", 2), "ǚ": ("ü", 3), "ǜ": ("ü", 4)
    ]
}
