import Foundation

struct ChineseLexicalDictionaryEntry: Equatable, Sendable {
    let traditional: String
    let simplified: String
    let numberedPinyin: String
    let toneMarkedPinyin: String
    let definitions: [String]

    var primaryGloss: String {
        definitions
            .filter { !$0.hasPrefix("CL:") }
            .prefix(2)
            .joined(separator: "; ")
    }
}

final class ChineseLexicalDictionary {
    static let shared = ChineseLexicalDictionary()

    private let entriesBySimplified: [String: [ChineseLexicalDictionaryEntry]]
    private let entriesByTraditional: [String: [ChineseLexicalDictionaryEntry]]

    convenience init(url: URL? = ChineseLexicalDictionary.defaultURL()) {
        let lines = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        self.init(cedictText: lines)
    }

    init(cedictText: String) {
        var simplified: [String: [ChineseLexicalDictionaryEntry]] = [:]
        var traditional: [String: [ChineseLexicalDictionaryEntry]] = [:]

        for line in cedictText.split(whereSeparator: \.isNewline) {
            guard let entry = Self.parseEntry(String(line)) else { continue }
            simplified[entry.simplified, default: []].append(entry)
            traditional[entry.traditional, default: []].append(entry)
        }

        entriesBySimplified = simplified.mapValues(Self.sortedEntries)
        entriesByTraditional = traditional.mapValues(Self.sortedEntries)
    }

    func bestEntry(for surface: String) -> ChineseLexicalDictionaryEntry? {
        entriesBySimplified[surface]?.first ?? entriesByTraditional[surface]?.first
    }

    func lexicalUnit(for surface: String, kind: ChineseLexicalUnit.Kind) -> ChineseLexicalUnit? {
        guard let entry = bestEntry(for: surface) else { return nil }
        return ChineseLexicalUnit(
            surface: surface,
            kind: kind,
            zhLatnPinyin: entry.toneMarkedPinyin,
            ipa: MandarinIPAConverter.ipa(fromPinyin: entry.toneMarkedPinyin),
            enGloss: entry.primaryGloss,
            annotationSource: AnnotationSource.dictionary.rawValue
        )
    }

    func characterUnit(for surface: String) -> ChineseCharacterUnit? {
        guard let entry = bestEntry(for: surface) else { return nil }
        return ChineseCharacterUnit(
            surface: surface,
            zhLatnPinyin: entry.toneMarkedPinyin,
            ipa: MandarinIPAConverter.ipa(fromPinyin: entry.toneMarkedPinyin),
            enGloss: entry.primaryGloss,
            annotationSource: AnnotationSource.dictionary.rawValue
        )
    }

    private static func parseEntry(_ line: String) -> ChineseLexicalDictionaryEntry? {
        guard !line.hasPrefix("#"),
              let pinyinStart = line.firstIndex(of: "["),
              let pinyinEnd = line[pinyinStart...].firstIndex(of: "]") else {
            return nil
        }

        let head = line[..<pinyinStart].split(separator: " ", maxSplits: 1)
        guard head.count == 2 else { return nil }

        var definitionsText = line[line.index(after: pinyinEnd)...].trimmingCharacters(in: .whitespaces)
        if definitionsText.hasPrefix("/") {
            definitionsText.removeFirst()
        }
        if definitionsText.hasSuffix("/") {
            definitionsText.removeLast()
        }

        let numberedPinyin = String(line[line.index(after: pinyinStart)..<pinyinEnd])
        let definitions = definitionsText
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.isEmpty }

        return ChineseLexicalDictionaryEntry(
            traditional: String(head[0]).trimmingCharacters(in: .whitespaces),
            simplified: String(head[1]).trimmingCharacters(in: .whitespaces),
            numberedPinyin: numberedPinyin,
            toneMarkedPinyin: toneMarkedPinyin(fromNumberedPinyin: numberedPinyin),
            definitions: definitions
        )
    }

    private static func sortedEntries(
        _ entries: [ChineseLexicalDictionaryEntry]
    ) -> [ChineseLexicalDictionaryEntry] {
        entries.sorted { lhs, rhs in
            let lhsProper = lhs.numberedPinyin.first?.isUppercase == true
            let rhsProper = rhs.numberedPinyin.first?.isUppercase == true
            if lhsProper != rhsProper {
                return !lhsProper
            }

            return lhs.definitions.count > rhs.definitions.count
        }
    }

    private static func defaultURL() -> URL? {
        if let bundleURL = Bundle.main.url(forResource: "cedict", withExtension: "txt") {
            return bundleURL
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("cedict.txt")
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            return sourceURL
        }

        let workingDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Shared/cedict.txt")
        if FileManager.default.fileExists(atPath: workingDirectoryURL.path) {
            return workingDirectoryURL
        }

        return nil
    }

    private static func toneMarkedPinyin(fromNumberedPinyin text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .map { toneMarkedSyllable(String($0)) }
            .joined(separator: " ")
    }

    private static func toneMarkedSyllable(_ syllable: String) -> String {
        var normalized = syllable
            .replacingOccurrences(of: "u:", with: "ü")
            .replacingOccurrences(of: "U:", with: "Ü")
        let tone = normalized.last?.wholeNumberValue ?? 5
        if normalized.last?.wholeNumberValue != nil {
            normalized.removeLast()
        }

        normalized = normalized.lowercased()
        guard (1...4).contains(tone),
              let vowelIndex = toneMarkIndex(in: normalized) else {
            return normalized
        }

        let character = normalized[vowelIndex]
        guard let marked = markedVowels[character]?[tone] else {
            return normalized
        }

        normalized.replaceSubrange(vowelIndex...vowelIndex, with: String(marked))
        return normalized
    }

    private static func toneMarkIndex(in syllable: String) -> String.Index? {
        for vowel in ["a", "e"] {
            if let index = syllable.firstIndex(of: Character(vowel)) {
                return index
            }
        }

        if let index = syllable.firstIndex(of: "o"),
           syllable[syllable.index(after: index)...].first == "u" {
            return index
        }

        return syllable.indices.reversed().first { index in
            markedVowels[syllable[index]] != nil
        }
    }

    private static let markedVowels: [Character: [Int: Character]] = [
        "a": [1: "ā", 2: "á", 3: "ǎ", 4: "à"],
        "e": [1: "ē", 2: "é", 3: "ě", 4: "è"],
        "i": [1: "ī", 2: "í", 3: "ǐ", 4: "ì"],
        "o": [1: "ō", 2: "ó", 3: "ǒ", 4: "ò"],
        "u": [1: "ū", 2: "ú", 3: "ǔ", 4: "ù"],
        "ü": [1: "ǖ", 2: "ǘ", 3: "ǚ", 4: "ǜ"]
    ]
}
