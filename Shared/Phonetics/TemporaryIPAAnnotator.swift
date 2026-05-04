import Foundation

enum TemporaryIPAAnnotator {
    static let placeholder = "lorem IPAsum"

    static func ipaPlaceholder(for text: String, languageCode: String) -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        return placeholder
    }
}
