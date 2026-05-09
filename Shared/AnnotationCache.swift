import Foundation

final class LocalAnnotationCache {
    static let shared = LocalAnnotationCache()

    private var storage: AnnotationCacheStorage
    private let url: URL
    private let queue = DispatchQueue(label: "AudioTranscription.LocalAnnotationCache")

    init(url: URL = LocalAnnotationCache.defaultURL) {
        self.url = url
        storage = Self.loadStorage(from: url)
    }

    func chineseCharacterUnit(surface: String, pinyin: String) -> ChineseCharacterUnit? {
        queue.sync {
            guard let unit = storage.chineseCharacterUnits[cacheKey(surface: surface, pinyin: pinyin)],
                  unit.isCharacterIPAUsable else {
                return nil
            }

            return unit
        }
    }

    func storeChineseCharacterUnit(_ unit: ChineseCharacterUnit) {
        guard unit.isCharacterIPAUsable else { return }

        queue.sync {
            storage.chineseCharacterUnits[cacheKey(surface: unit.surface, pinyin: unit.zhLatnPinyin)] = unit
            saveStorage()
        }
    }

    func chineseLexicalUnit(surface: String, kind: ChineseLexicalUnit.Kind) -> ChineseLexicalUnit? {
        queue.sync {
            storage.chineseLexicalUnits[lexicalCacheKey(surface: surface, kind: kind)]
        }
    }

    func storeChineseLexicalUnit(_ unit: ChineseLexicalUnit) {
        guard unit.isAnnotationUsable else { return }

        queue.sync {
            storage.chineseLexicalUnits[lexicalCacheKey(surface: unit.surface, kind: unit.kind)] = unit
            saveStorage()
        }
    }

    private func saveStorage() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(storage)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            assertionFailure("Could not save annotation cache: \(error.localizedDescription)")
        }
    }

    private func cacheKey(surface: String, pinyin: String) -> String {
        "zh.character.v1|\(surface)|\(pinyin)"
    }

    private func lexicalCacheKey(surface: String, kind: ChineseLexicalUnit.Kind) -> String {
        "zh.lexical.v1|\(kind.rawValue)|\(surface)"
    }

    private static func loadStorage(from url: URL) -> AnnotationCacheStorage {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AnnotationCacheStorage.self, from: data)
        } catch {
            return AnnotationCacheStorage()
        }
    }

    private static var defaultURL: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("AudioTranscription", isDirectory: true)
            .appendingPathComponent("annotation-cache-v1.json")
    }
}

private struct AnnotationCacheStorage: Codable {
    var chineseCharacterUnits: [String: ChineseCharacterUnit] = [:]
    var chineseLexicalUnits: [String: ChineseLexicalUnit] = [:]
}

private extension ChineseLexicalUnit {
    var isAnnotationUsable: Bool {
        !zhLatnPinyin.isEmpty || !ipa.isEmpty || !enGloss.isEmpty
    }
}
