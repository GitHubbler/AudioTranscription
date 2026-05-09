import Foundation

extension SegmentRecord {
    var isAbleToShowPhoneticGrid: Bool {
        !zhText.trimmedForDisplay.isEmpty && !phoneticCells.isEmpty
    }

    var phoneticCells: [PhoneticCell] {
        let characterUnits = zhCharacterUnits.isEmpty
            ? ChineseCharacterAnnotator.units(from: zhText)
            : zhCharacterUnits

        if !characterUnits.isEmpty {
            return characterUnits.enumerated().map { index, unit in
                PhoneticCell(
                    index: index,
                    hanzi: unit.surface,
                    pinyin: unit.zhLatnPinyin,
                    ipa: unit.displayIPA,
                    english: unit.enGloss
                )
            }
        }

        let characters = zhText
            .filter { !$0.isWhitespace }
            .map(String.init)

        guard !characters.isEmpty else { return [] }

        return characters.enumerated().map { index, character in
            PhoneticCell(
                index: index,
                hanzi: character,
                pinyin: "",
                ipa: TemporaryIPAAnnotator.ipaPlaceholder(for: character, languageCode: "zh"),
                english: ""
            )
        }
    }
}
