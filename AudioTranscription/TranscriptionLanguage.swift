import Foundation

struct TranscriptionLanguage: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let localeIdentifier: String?

    var locale: Locale? {
        localeIdentifier.map(Locale.init(identifier:))
    }

    var languageCode: String? {
        localeIdentifier?.normalizedLanguageCode
    }

    static let automatic = TranscriptionLanguage(id: "auto", name: "Auto", localeIdentifier: nil)

    static let choices: [TranscriptionLanguage] = [
        .automatic,
        .init(id: "en-US", name: "English", localeIdentifier: "en_US"),
        .init(id: "zh-Hans", name: "Chinese Simplified", localeIdentifier: "zh_Hans"),
        .init(id: "zh-Hant", name: "Chinese Traditional", localeIdentifier: "zh_Hant"),
        .init(id: "ja-JP", name: "Japanese", localeIdentifier: "ja_JP"),
        .init(id: "ko-KR", name: "Korean", localeIdentifier: "ko_KR"),
        .init(id: "fr-FR", name: "French", localeIdentifier: "fr_FR"),
        .init(id: "es-ES", name: "Spanish", localeIdentifier: "es_ES"),
        .init(id: "de-DE", name: "German", localeIdentifier: "de_DE"),
        .init(id: "it-IT", name: "Italian", localeIdentifier: "it_IT")
    ]
}

extension String {
    var normalizedLanguageCode: String? {
        split { character in
            character == "_" || character == "-"
        }
        .first
        .map { String($0).lowercased() }
    }
}
