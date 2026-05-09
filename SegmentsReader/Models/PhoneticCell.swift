import Foundation

struct PhoneticCell: Identifiable, Equatable {
    let index: Int
    let hanzi: String
    let pinyin: String
    let ipa: String
    let english: String

    var id: Int { index }
}
