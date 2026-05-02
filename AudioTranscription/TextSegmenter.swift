import Foundation

struct TextSegment: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let sourceRange: Range<String.Index>?
}

struct TextSegmenter {
    func sentenceSegments(from text: String) -> [TextSegment] {
        var segments: [TextSegment] = []

        for block in textBlocks(from: text) {
            let sentences = sentenceRanges(in: text, range: block).flatMap { sentence in
                supplementalSentenceRanges(in: text, range: sentence)
            }.flatMap { sentence in
                chinesePhraseBoundaryRanges(in: text, range: sentence)
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
            TextSegment(id: index + 1, text: segment.text, sourceRange: segment.sourceRange)
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
        range: Range<String.Index>
    ) -> [Range<String.Index>] {
        let candidate = String(text[range])
        guard containsCJK(candidate) else { return [range] }
        guard supplementalTerminatorCount(in: candidate) <= 1 else { return [range] }

        var boundaries = Set<String.Index>()
        addChineseTopicBoundaries(in: text, range: range, to: &boundaries)
        addChineseListToStatisticBoundaries(in: text, range: range, to: &boundaries)

        return rangesBySplitting(range, at: boundaries)
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
                sourceRange: mergedRange..<trimmedRange.upperBound
            )
            return
        }

        let segment = TextSegment(
            id: segments.count + 1,
            text: trimmedText,
            sourceRange: trimmedRange
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
