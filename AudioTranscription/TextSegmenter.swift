import Foundation

struct TextSegment: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let sourceRange: Range<String.Index>?
    let localValue: TextSegmentValue

    func withSourceLanguage(_ sourceLang: String) -> TextSegment {
        TextSegment(
            id: id,
            text: text,
            sourceRange: sourceRange,
            localValue: TextSegmentValue(sourceLang: sourceLang, sourceText: text)
        )
    }
}

struct TextSegmentationContext: Sendable {
    var timedSegments: [TimedTranscriptionSegment]
    var audioBoundaryHints: [AudioBoundaryHint]
    var audioDuration: TimeInterval?

    static let empty = TextSegmentationContext(
        timedSegments: [],
        audioBoundaryHints: [],
        audioDuration: nil
    )
}

struct TextSegmenter {
    func sentenceSegments(
        from text: String,
        context: TextSegmentationContext = .empty
    ) -> [TextSegment] {
        var segments: [TextSegment] = []

        for block in textBlocks(from: text) {
            let sentences = sentenceRanges(in: text, range: block).flatMap { sentence in
                supplementalSentenceRanges(in: text, range: sentence)
            }.flatMap { sentence in
                chinesePhraseBoundaryRanges(in: text, range: sentence, context: context)
            }

            if sentences.isEmpty {
                appendSegment(from: block, in: text, to: &segments)
            } else {
                for sentence in sentences {
                    appendSegment(from: sentence, in: text, to: &segments)
                }
            }
        }

        return segments.enumerated().map { index, segment in
            TextSegment(
                id: index + 1,
                text: segment.text,
                sourceRange: segment.sourceRange,
                localValue: segment.localValue
            )
        }
    }

    func renderSentenceList(_ segments: [TextSegment]) -> String {
        segments.map(\.text).joined(separator: "\n")
    }

    private func textBlocks(from text: String) -> [Range<String.Index>] {
        var blocks: [Range<String.Index>] = []
        var blockStart: String.Index?
        var currentIndex = text.startIndex

        while currentIndex < text.endIndex {
            let character = text[currentIndex]

            if character.isNewline {
                if let start = blockStart, start < currentIndex {
                    blocks.append(start..<currentIndex)
                }
                blockStart = nil
            } else if blockStart == nil {
                blockStart = currentIndex
            }

            currentIndex = text.index(after: currentIndex)
        }

        if let start = blockStart, start < text.endIndex {
            blocks.append(start..<text.endIndex)
        }

        return blocks
    }

    private func sentenceRanges(in text: String, range: Range<String.Index>) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []

        text.enumerateSubstrings(in: range, options: [.bySentences, .localized]) { _, sentenceRange, _, _ in
            ranges.append(sentenceRange)
        }

        return ranges
    }

    private func supplementalSentenceRanges(
        in text: String,
        range: Range<String.Index>
    ) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var sentenceStart = range.lowerBound
        var currentIndex = range.lowerBound

        while currentIndex < range.upperBound {
            let character = text[currentIndex]
            currentIndex = text.index(after: currentIndex)

            guard isSupplementalSentenceTerminator(character) else {
                continue
            }

            var sentenceEnd = currentIndex
            while sentenceEnd < range.upperBound, isClosingSentencePunctuation(text[sentenceEnd]) {
                sentenceEnd = text.index(after: sentenceEnd)
            }

            ranges.append(sentenceStart..<sentenceEnd)
            sentenceStart = sentenceEnd
            currentIndex = sentenceEnd
        }

        if sentenceStart < range.upperBound {
            ranges.append(sentenceStart..<range.upperBound)
        }

        return ranges.isEmpty ? [range] : ranges
    }

    private func chinesePhraseBoundaryRanges(
        in text: String,
        range: Range<String.Index>,
        context: TextSegmentationContext
    ) -> [Range<String.Index>] {
        let candidate = String(text[range])
        guard containsCJK(candidate) else { return [range] }
        guard supplementalTerminatorCount(in: candidate) <= 1 else { return [range] }

        var boundaries = Set<String.Index>()
        addAudioHintBoundaries(in: text, range: range, context: context, to: &boundaries)
        addChineseTopicBoundaries(in: text, range: range, to: &boundaries)
        addChineseListToStatisticBoundaries(in: text, range: range, to: &boundaries)

        return rangesBySplitting(range, at: boundaries)
    }

    private func addAudioHintBoundaries(
        in text: String,
        range: Range<String.Index>,
        context: TextSegmentationContext,
        to boundaries: inout Set<String.Index>
    ) {
        guard let audioDuration = context.audioDuration, audioDuration > 0 else { return }
        guard !context.audioBoundaryHints.isEmpty else { return }

        for hint in context.audioBoundaryHints where hint.midpoint > 0 && hint.midpoint < audioDuration {
            guard let approximateOffset = approximateCharacterOffset(
                for: hint,
                audioDuration: audioDuration,
                context: context,
                textRange: range,
                in: text
            ) else {
                continue
            }

            let boundary = snappedBoundary(
                nearCharacterOffset: approximateOffset,
                in: text,
                range: range,
                isAllowingApproximateCJKBoundary: hint.confidence >= 0.45 || hint.duration >= 0.24
            )

            if let boundary {
                boundaries.insert(boundary)
            }
        }
    }

    private func approximateCharacterOffset(
        for hint: AudioBoundaryHint,
        audioDuration: TimeInterval,
        context: TextSegmentationContext,
        textRange: Range<String.Index>,
        in text: String
    ) -> Int? {
        let rangeLength = text.distance(from: textRange.lowerBound, to: textRange.upperBound)
        guard rangeLength > 0 else { return nil }

        if let timedOffset = approximateOffsetFromTimedSegments(for: hint, context: context, rangeLength: rangeLength) {
            return timedOffset
        }

        let ratio = min(1, max(0, hint.midpoint / audioDuration))
        return Int((Double(rangeLength) * ratio).rounded())
    }

    private func approximateOffsetFromTimedSegments(
        for hint: AudioBoundaryHint,
        context: TextSegmentationContext,
        rangeLength: Int
    ) -> Int? {
        let segments = context.timedSegments
            .filter { !$0.text.isEmpty }
            .sorted { $0.start < $1.start }
        guard !segments.isEmpty else { return nil }

        let originalLength = segments.reduce(0) { length, segment in
            length + segment.text.count + 1
        }
        guard originalLength > 0 else { return nil }

        let boundaryTime = hint.midpoint
        var charactersBeforeBoundary = 0
        var foundFollowingSegment = false
        for segment in segments {
            if segment.start >= boundaryTime {
                foundFollowingSegment = true
                break
            }
            charactersBeforeBoundary += segment.text.count + 1
        }
        guard foundFollowingSegment else { return nil }

        let ratio = min(1, max(0, Double(charactersBeforeBoundary) / Double(originalLength)))
        return Int((Double(rangeLength) * ratio).rounded())
    }

    private func snappedBoundary(
        nearCharacterOffset offset: Int,
        in text: String,
        range: Range<String.Index>,
        isAllowingApproximateCJKBoundary: Bool
    ) -> String.Index? {
        let rangeLength = text.distance(from: range.lowerBound, to: range.upperBound)
        guard rangeLength >= 8 else { return nil }

        let clampedOffset = min(max(offset, 1), rangeLength - 1)
        let approximateIndex = text.index(range.lowerBound, offsetBy: clampedOffset)
        let maxDistance = max(4, min(16, rangeLength / 5))

        let candidates = boundaryCandidates(in: text, range: range)
            .map { candidate in
                (index: candidate, distance: abs(text.distance(from: approximateIndex, to: candidate)))
            }
            .filter { $0.distance <= maxDistance }
            .sorted { lhs, rhs in
                if lhs.distance == rhs.distance {
                    return lhs.index < rhs.index
                }
                return lhs.distance < rhs.distance
            }

        if let candidate = candidates.first?.index,
           isReasonableSplit(candidate, in: text, range: range) {
            return candidate
        }

        guard isAllowingApproximateCJKBoundary else { return nil }
        guard isReasonableSplit(approximateIndex, in: text, range: range) else { return nil }
        guard !isInsideProtectedToken(approximateIndex, in: text, range: range) else { return nil }
        return approximateIndex
    }

    private func boundaryCandidates(in text: String, range: Range<String.Index>) -> [String.Index] {
        var candidates = Set<String.Index>()
        var currentIndex = range.lowerBound

        while currentIndex < range.upperBound {
            let character = text[currentIndex]
            let nextIndex = text.index(after: currentIndex)

            if character.isWhitespace {
                if !isAdjacentToNonHanziNumber(at: currentIndex, in: text, range: range) {
                    candidates.insert(currentIndex)
                    if nextIndex < range.upperBound {
                        candidates.insert(nextIndex)
                    }
                }
            }

            if isSupplementalSentenceTerminator(character) {
                candidates.insert(nextIndex)
            }

            currentIndex = nextIndex
        }

        addChineseTopicBoundaries(in: text, range: range, to: &candidates)
        addChineseListToStatisticBoundaries(in: text, range: range, to: &candidates)
        return Array(candidates)
    }

    private func isReasonableSplit(
        _ index: String.Index,
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        let before = text.distance(from: range.lowerBound, to: index)
        let after = text.distance(from: index, to: range.upperBound)
        return before >= 4 && after >= 4
    }

    private func isInsideProtectedToken(
        _ index: String.Index,
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        guard index > range.lowerBound, index < range.upperBound else { return false }
        let previous = text[text.index(before: index)]
        let next = text[index]

        if previous.isNumber && next.isNumber {
            return true
        }

        if (previous.isLetter || previous.isNumber) && (next.isLetter || next.isNumber) {
            return true
        }

        if text[index].isWhitespace, isAdjacentToNonHanziNumber(at: index, in: text, range: range) {
            return true
        }

        if isNonHanziNumber(previous) || isNonHanziNumber(next) {
            return true
        }

        return previous == "." || next == "."
    }

    private func isAdjacentToNonHanziNumber(
        at index: String.Index,
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        if let previous = previousNonWhitespaceCharacter(before: index, in: text, lowerBound: range.lowerBound),
           isNonHanziNumber(previous) {
            return true
        }

        if let next = nextNonWhitespaceCharacter(after: index, in: text, upperBound: range.upperBound),
           isNonHanziNumber(next) {
            return true
        }

        return false
    }

    private func previousNonWhitespaceCharacter(
        before index: String.Index,
        in text: String,
        lowerBound: String.Index
    ) -> Character? {
        var currentIndex = index
        while currentIndex > lowerBound {
            currentIndex = text.index(before: currentIndex)
            let character = text[currentIndex]
            if !character.isWhitespace {
                return character
            }
        }
        return nil
    }

    private func nextNonWhitespaceCharacter(
        after index: String.Index,
        in text: String,
        upperBound: String.Index
    ) -> Character? {
        var currentIndex = text.index(after: index)
        while currentIndex < upperBound {
            let character = text[currentIndex]
            if !character.isWhitespace {
                return character
            }
            currentIndex = text.index(after: currentIndex)
        }
        return nil
    }

    private func isNonHanziNumber(_ character: Character) -> Bool {
        character.isNumber || character == "." || character == "%"
    }

    private func addChineseTopicBoundaries(
        in text: String,
        range: Range<String.Index>,
        to boundaries: inout Set<String.Index>
    ) {
        let markers = ["本期", "本次", "此次", "此外", "同时", "其中"]

        for marker in markers {
            var searchStart = range.lowerBound
            while searchStart < range.upperBound,
                  let markerRange = text.range(of: marker, range: searchStart..<range.upperBound) {
                if markerRange.lowerBound > range.lowerBound {
                    boundaries.insert(markerRange.lowerBound)
                }
                searchStart = markerRange.upperBound
            }
        }
    }

    private func addChineseListToStatisticBoundaries(
        in text: String,
        range: Range<String.Index>,
        to boundaries: inout Set<String.Index>
    ) {
        let listClosers = ["板块", "类别", "品类", "领域"]

        for closer in listClosers {
            var searchStart = range.lowerBound
            while searchStart < range.upperBound,
                  let closerRange = text.range(of: closer, range: searchStart..<range.upperBound) {
                let boundary = closerRange.upperBound
                if isFollowedByStatisticClause(in: text, from: boundary, upperBound: range.upperBound) {
                    boundaries.insert(boundary)
                }
                searchStart = closerRange.upperBound
            }
        }
    }

    private func isFollowedByStatisticClause(
        in text: String,
        from index: String.Index,
        upperBound: String.Index
    ) -> Bool {
        guard let firstNonWhitespace = firstNonWhitespaceIndex(in: text, from: index, upperBound: upperBound) else {
            return false
        }
        guard text[firstNonWhitespace].isNumber else {
            return false
        }

        var digitEnd = firstNonWhitespace
        while digitEnd < upperBound, text[digitEnd].isNumber {
            digitEnd = text.index(after: digitEnd)
        }

        guard digitEnd < upperBound else { return false }
        let suffix = String(text[digitEnd..<upperBound])
        return suffix.hasPrefix("个") || suffix.hasPrefix("项") || suffix.hasPrefix("类")
    }

    private func firstNonWhitespaceIndex(
        in text: String,
        from index: String.Index,
        upperBound: String.Index
    ) -> String.Index? {
        var currentIndex = index
        while currentIndex < upperBound {
            if !text[currentIndex].isWhitespace {
                return currentIndex
            }
            currentIndex = text.index(after: currentIndex)
        }
        return nil
    }

    private func rangesBySplitting(
        _ range: Range<String.Index>,
        at boundaries: Set<String.Index>
    ) -> [Range<String.Index>] {
        let sortedBoundaries = boundaries
            .filter { range.contains($0) && $0 > range.lowerBound && $0 < range.upperBound }
            .sorted()

        guard !sortedBoundaries.isEmpty else { return [range] }

        var ranges: [Range<String.Index>] = []
        var lowerBound = range.lowerBound
        for boundary in sortedBoundaries {
            ranges.append(lowerBound..<boundary)
            lowerBound = boundary
        }
        ranges.append(lowerBound..<range.upperBound)
        return ranges
    }

    private func appendSegment(
        from range: Range<String.Index>,
        in text: String,
        to segments: inout [TextSegment]
    ) {
        let trimmedRange = trimmedRange(range, in: text)
        guard let trimmedRange else { return }

        let trimmedText = String(text[trimmedRange])
        if isStandaloneSentencePunctuation(trimmedText), let previous = segments.last {
            let mergedRange = previous.sourceRange?.lowerBound ?? trimmedRange.lowerBound
            segments[segments.count - 1] = TextSegment(
                id: previous.id,
                text: previous.text + trimmedText,
                sourceRange: mergedRange..<trimmedRange.upperBound,
                localValue: TextSegmentValue(sourceText: previous.text + trimmedText)
            )
            return
        }

        let segment = TextSegment(
            id: segments.count + 1,
            text: trimmedText,
            sourceRange: trimmedRange,
            localValue: TextSegmentValue(sourceText: trimmedText)
        )
        segments.append(segment)
    }

    private func trimmedRange(_ range: Range<String.Index>, in text: String) -> Range<String.Index>? {
        var lowerBound = range.lowerBound
        var upperBound = range.upperBound

        while lowerBound < upperBound, text[lowerBound].isWhitespace {
            lowerBound = text.index(after: lowerBound)
        }

        while lowerBound < upperBound {
            let previous = text.index(before: upperBound)
            guard text[previous].isWhitespace else { break }
            upperBound = previous
        }

        return lowerBound < upperBound ? lowerBound..<upperBound : nil
    }

    private func isSupplementalSentenceTerminator(_ character: Character) -> Bool {
        switch character {
        case "。", "｡", "？", "?", "！", "!":
            return true
        default:
            return false
        }
    }

    private func isClosingSentencePunctuation(_ character: Character) -> Bool {
        switch character {
        case "\"", "'", "”", "’", "」", "』", "）", ")", "]", "】", "》":
            return true
        default:
            return false
        }
    }

    private func isStandaloneSentencePunctuation(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { character in
            isSupplementalSentenceTerminator(character) || isClosingSentencePunctuation(character)
        }
    }

    private func supplementalTerminatorCount(in text: String) -> Int {
        text.reduce(0) { count, character in
            isSupplementalSentenceTerminator(character) ? count + 1 : count
        }
    }

    private func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }
}
