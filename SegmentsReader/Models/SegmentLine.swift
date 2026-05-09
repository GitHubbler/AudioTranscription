import SwiftUI

struct SegmentLine: Identifiable {
    enum Role: Hashable {
        case source
        case sourcePhonetics
        case translation
        case translationPhonetics
    }

    let role: Role
    let text: String

    var id: Role { role }

    var font: Font { role.font }

    var color: HierarchicalShapeStyle {
        switch role {
        case .source:
            return .primary
        case .sourcePhonetics:
            return .secondary
        case .translation:
            return .primary
        case .translationPhonetics:
            return .secondary
        }
    }

    var lineSpacing: CGFloat {
        role == .source ? 3 : 2
    }

    static func lines(for record: SegmentRecord) -> [SegmentLine] {
        switch record.sourceLang {
        case "zh":
            return [
                line(.source, record.zhText),
                line(.sourcePhonetics, record.zhLatnPinyin),
                line(.translation, record.enText)
            ].compactMap { $0 }
        case "en":
            return [
                line(.source, record.enText),
                line(.translation, record.zhText),
                line(.translationPhonetics, record.zhLatnPinyin)
            ].compactMap { $0 }
        case "de":
            return [
                line(.source, record.deText),
                line(.translation, record.zhText),
                line(.translationPhonetics, record.zhLatnPinyin)
            ].compactMap { $0 }
        case "ro":
            return [
                line(.source, record.roText),
                line(.translation, record.zhText),
                line(.translationPhonetics, record.zhLatnPinyin)
            ].compactMap { $0 }
        default:
            return [
                line(.source, record.zhText),
                line(.sourcePhonetics, record.zhLatnPinyin),
                line(.translation, record.enText)
            ].compactMap { $0 }
        }
    }

    private static func line(_ role: Role, _ text: String) -> SegmentLine? {
        let trimmed = text.trimmedForDisplay
        guard !trimmed.isEmpty else { return nil }
        return SegmentLine(role: role, text: trimmed)
    }
}

extension SegmentLine.Role {
    var font: Font {
        switch self {
        case .source:
            return .system(.title3, design: .default).weight(.semibold)
        case .sourcePhonetics:
            return .system(.body, design: .rounded)
        case .translation:
            return .system(.body, design: .default)
        case .translationPhonetics:
            return .system(.callout, design: .rounded)
        }
    }
}
