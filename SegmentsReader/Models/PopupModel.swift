import SwiftUI

@MainActor
final class PopupModel: ObservableObject {
    @Published var activeCell: PhoneticCell?
    @Published var activeSegment: ReaderSegment?
    
    @AppStorage("PopupPosition.x") var positionX: Double = 300
    @AppStorage("PopupPosition.y") var positionY: Double = 150
    
    var position: CGPoint {
        get { CGPoint(x: positionX, y: positionY) }
        set {
            positionX = Double(newValue.x)
            positionY = Double(newValue.y)
        }
    }
    
    var allSegments: [ReaderSegment] = []
    var currentGridColumns: Int = 1
    
    func navigate(dx: Int, dy: Int) {
        guard let cell = activeCell, let segment = activeSegment else { return }
        
        let cells = segment.record.phoneticCells
        guard !cells.isEmpty else { return }
        
        var newIndex = cell.index
        
        if dx != 0 {
            newIndex += dx
        }
        if dy != 0 {
            newIndex += dy * max(1, currentGridColumns)
        }
        
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
