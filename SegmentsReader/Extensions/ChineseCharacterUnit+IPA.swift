import Foundation

extension ChineseCharacterUnit {
    var displayIPA: String {
        isCharacterIPAUsable ? ipa : MandarinIPAConverter.ipa(fromPinyin: zhLatnPinyin)
    }
}
