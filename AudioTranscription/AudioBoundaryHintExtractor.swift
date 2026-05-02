import AVFoundation
import Foundation

struct AudioBoundaryAnalysis: Sendable {
    let duration: TimeInterval
    let hints: [AudioBoundaryHint]
}

struct AudioBoundaryHint: Equatable, Sendable {
    let time: TimeInterval
    let duration: TimeInterval
    let confidence: Double

    var midpoint: TimeInterval {
        time + duration / 2
    }
}

struct AudioBoundaryHintExtractor: Sendable {
    var windowDuration: TimeInterval = 0.02
    var minimumSilenceDuration: TimeInterval = 0.18
    var leadingMargin: TimeInterval = 0.3
    var trailingMargin: TimeInterval = 0.5

    func analyze(fileURL: URL) throws -> AudioBoundaryAnalysis {
        let audioFile = try AVAudioFile(forReading: fileURL)
        let sampleRate = audioFile.processingFormat.sampleRate
        let duration = sampleRate > 0 ? Double(audioFile.length) / sampleRate : 0
        guard sampleRate > 0, duration > 0 else {
            return AudioBoundaryAnalysis(duration: duration, hints: [])
        }

        let windows = try amplitudeWindows(from: audioFile, sampleRate: sampleRate)
        guard !windows.isEmpty else {
            return AudioBoundaryAnalysis(duration: duration, hints: [])
        }

        let threshold = silenceThreshold(for: windows.map(\.decibels))
        let hints = silenceSpans(in: windows, duration: duration, threshold: threshold)

        return AudioBoundaryAnalysis(duration: duration, hints: hints)
    }

    private func amplitudeWindows(from audioFile: AVAudioFile, sampleRate: Double) throws -> [AmplitudeWindow] {
        let frameCapacity = AVAudioFrameCount(max(1, Int(sampleRate * windowDuration)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCapacity) else {
            return []
        }

        var windows: [AmplitudeWindow] = []

        while audioFile.framePosition < audioFile.length {
            let startFrame = audioFile.framePosition
            let remainingFrames = AVAudioFrameCount(audioFile.length - startFrame)
            try audioFile.read(into: buffer, frameCount: min(frameCapacity, remainingFrames))

            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { break }

            let start = Double(startFrame) / sampleRate
            let duration = Double(frameLength) / sampleRate
            windows.append(AmplitudeWindow(
                start: start,
                duration: duration,
                decibels: decibels(in: buffer, frameLength: frameLength)
            ))
        }

        return windows
    }

    private func decibels(in buffer: AVAudioPCMBuffer, frameLength: Int) -> Double {
        guard let channels = buffer.floatChannelData else {
            return -100
        }

        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return -100 }

        var sumOfSquares = 0.0
        for channelIndex in 0..<channelCount {
            let channel = channels[channelIndex]
            for frameIndex in 0..<frameLength {
                let sample = Double(channel[frameIndex])
                sumOfSquares += sample * sample
            }
        }

        let meanSquare = sumOfSquares / Double(frameLength * channelCount)
        let rms = sqrt(meanSquare)
        return 20 * log10(max(rms, 0.000_001))
    }

    private func silenceThreshold(for decibels: [Double]) -> Double {
        let sorted = decibels.sorted()
        guard let quiet = percentile(0.15, in: sorted),
              let loud = percentile(0.85, in: sorted)
        else {
            return -35
        }

        return min(-30, max(-45, quiet + (loud - quiet) * 0.3))
    }

    private func percentile(_ percentile: Double, in sortedValues: [Double]) -> Double? {
        guard !sortedValues.isEmpty else { return nil }
        let clampedPercentile = min(1, max(0, percentile))
        let index = Int((Double(sortedValues.count - 1) * clampedPercentile).rounded())
        return sortedValues[index]
    }

    private func silenceSpans(
        in windows: [AmplitudeWindow],
        duration: TimeInterval,
        threshold: Double
    ) -> [AudioBoundaryHint] {
        var hints: [AudioBoundaryHint] = []
        var silenceStart: TimeInterval?
        var silenceEnd: TimeInterval?

        for window in windows {
            if window.decibels <= threshold {
                if silenceStart == nil {
                    silenceStart = window.start
                }
                silenceEnd = window.start + window.duration
            } else if let start = silenceStart, let end = silenceEnd {
                appendHint(from: start, to: end, duration: duration, to: &hints)
                silenceStart = nil
                silenceEnd = nil
            }
        }

        if let start = silenceStart, let end = silenceEnd {
            appendHint(from: start, to: end, duration: duration, to: &hints)
        }

        return hints
    }

    private func appendHint(
        from start: TimeInterval,
        to end: TimeInterval,
        duration audioDuration: TimeInterval,
        to hints: inout [AudioBoundaryHint]
    ) {
        let duration = end - start
        guard duration >= minimumSilenceDuration else { return }
        guard start >= leadingMargin, end <= audioDuration - trailingMargin else { return }

        let confidence = min(1, max(0.25, duration / 0.6))
        hints.append(AudioBoundaryHint(time: start, duration: duration, confidence: confidence))
    }
}

private struct AmplitudeWindow {
    let start: TimeInterval
    let duration: TimeInterval
    let decibels: Double
}
