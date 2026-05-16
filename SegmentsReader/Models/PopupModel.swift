import SwiftUI

@Observable
@MainActor
final class PopupModel {
    var activeCell: PhoneticCell?
    var activeSegment: ReaderSegment?

    // Persisted via didSet + manual init — @AppStorage conflicts with @Observable's
    // accessor synthesis so we manage persistence ourselves (same pattern as SegmentsReaderModel).
    @ObservationIgnored var positionX: Double = 300 {
        didSet { UserDefaults.standard.set(positionX, forKey: "PopupPosition.x") }
    }
    @ObservationIgnored var positionY: Double = 150 {
        didSet { UserDefaults.standard.set(positionY, forKey: "PopupPosition.y") }
    }
    var showsIPA: Bool = true {
        didSet { UserDefaults.standard.set(showsIPA, forKey: "Popup.showsIPA") }
    }

    // Navigation support — not observed by views directly.
    @ObservationIgnored var allSegments: [ReaderSegment] = []
    @ObservationIgnored var currentGridColumns: Int = 1

    var position: CGPoint {
        get { CGPoint(x: positionX, y: positionY) }
        set {
            positionX = Double(newValue.x)
            positionY = Double(newValue.y)
        }
    }

    init() {
        let ud = UserDefaults.standard
        if let x   = ud.object(forKey: "PopupPosition.x")  as? Double { positionX = x }
        if let y   = ud.object(forKey: "PopupPosition.y")  as? Double { positionY = y }
        if let ipa = ud.object(forKey: "Popup.showsIPA")   as? Bool   { showsIPA = ipa }
    }

    // MARK: - Navigation

    func navigate(dx: Int, dy: Int) {
        guard let cell = activeCell, let segment = activeSegment else { return }

        let cells = segment.record.phoneticCells
        guard !cells.isEmpty else { return }

        var newIndex = cell.index

        if dx != 0 { newIndex += dx }
        if dy != 0 { newIndex += dy * max(1, currentGridColumns) }

        if newIndex >= 0 && newIndex < cells.count {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                activeCell = cells[newIndex]
            }
        } else {
            if newIndex < 0 {
                if let segIndex = allSegments.firstIndex(where: { $0.id == segment.id }), segIndex > 0 {
                    let prevSegment = allSegments[segIndex - 1]
                    let prevCells = prevSegment.record.phoneticCells
                    if !prevCells.isEmpty {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            activeSegment = prevSegment
                            activeCell = prevCells.last
                        }
                    }
                }
            } else {
                if let segIndex = allSegments.firstIndex(where: { $0.id == segment.id }), segIndex < allSegments.count - 1 {
                    let nextSegment = allSegments[segIndex + 1]
                    let nextCells = nextSegment.record.phoneticCells
                    if !nextCells.isEmpty {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            activeSegment = nextSegment
                            activeCell = nextCells.first
                        }
                    }
                }
            }
        }
    }

    func navigateToExtreme(isFirst: Bool) {
        guard let segment = activeSegment else { return }
        let cells = segment.record.phoneticCells
        guard !cells.isEmpty else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            activeCell = isFirst ? cells.first : cells.last
        }
    }
}
