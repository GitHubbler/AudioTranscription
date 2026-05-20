#if os(macOS)
import AppKit
#endif
import SwiftUI
import AVFoundation

@Observable
@MainActor
final class SegmentsReaderModel {
    private(set) var fileURL: URL?
    private(set) var segments: [ReaderSegment] = []
    private(set) var statusText = "Open segmented JSON"
    private(set) var errorText: String?
    private(set) var playingSegmentID: Int?

    /// Read-only externally; mutate via setPlaybackSpeed(_:) to keep live-player
    /// side-effect co-located with the persistence write.
    private(set) var playbackSpeed: Float = 1.0

    var isLooping: Bool = false {
    didSet {
        UserDefaults.standard.set(isLooping, forKey: Self.isLoopingKey)
        if playingSegmentID != nil { restartPlaybackIfNeeded() }
    }
}
    var loopGap: TimeInterval = 0.0 {
    didSet {
        UserDefaults.standard.set(loopGap, forKey: Self.loopGapKey)
        if playingSegmentID != nil { restartPlaybackIfNeeded() }
    }
}

    var timeOffset: Double = 0.0 {
    didSet {
        UserDefaults.standard.set(timeOffset, forKey: Self.timeOffsetKey)
        if playingSegmentID != nil { restartPlaybackIfNeeded() }
    }
}
    
    /// Seconds added to every segment's out point at playback time. Default is 0.
    var outpointOffset: Double = 0.0 {
    didSet {
        UserDefaults.standard.set(outpointOffset, forKey: Self.outpointOffsetKey)
        if playingSegmentID != nil { restartPlaybackIfNeeded() }
    }
}

    var isNotEmptySegments: Bool { !segments.isEmpty }

    // MARK: - Private keys & implementation state

    private static let lastURLKey    = "LastOpenedFileURL"
    private static let speedKey      = "PlaybackSpeed"
    private static let isLoopingKey  = "IsLooping"
    private static let loopGapKey    = "LoopGap"
    private static let timeOffsetKey = "TimeOffset"
    private static let outpointOffsetKey = "OutpointOffset"

    // These properties change frequently during playback and must never
    // trigger view observation updates.
    @ObservationIgnored private var audioPlayer: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var isSchedulingLoop = false

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard
        if let speed = ud.object(forKey: Self.speedKey) as? Float {
            playbackSpeed = speed
        }
        isLooping  = ud.bool(forKey: Self.isLoopingKey)
        loopGap    = ud.double(forKey: Self.loopGapKey)
        timeOffset = ud.double(forKey: Self.timeOffsetKey)
        outpointOffset = ud.double(forKey: Self.outpointOffsetKey)
    }

    // MARK: - Public interface

    /// Sets playback speed, persists it, and applies it to the running player immediately.
    func setPlaybackSpeed(_ value: Float) {
        playbackSpeed = value
        UserDefaults.standard.set(value, forKey: Self.speedKey)
        if let player = audioPlayer {
            player.defaultRate = value
            if player.rate > 0 { player.rate = value }
        }
    }

    func playAudio(for segment: ReaderSegment) {
        if playingSegmentID == segment.id {
            stopAudio()
            return
        }

        stopAudio()

        guard let rawInPoint = segment.record.audioInPoint,
              let rawOutPoint = segment.record.audioOutPoint,
              let audioName = segment.record.sourceAudio,
              let jsonURL = fileURL else { return }

        // Apply the calibration offsets; clamp in-point to ≥ 0.
        let inPoint  = max(0, rawInPoint  + timeOffset)
        let outPoint = max(inPoint + 0.01, rawOutPoint + outpointOffset)

        let audioURL = jsonURL.deletingLastPathComponent().appendingPathComponent(audioName)
        let playerItem = AVPlayerItem(url: audioURL)
        let player = AVPlayer(playerItem: playerItem)

        self.audioPlayer = player
        self.playingSegmentID = segment.id

        let inTime = CMTime(seconds: inPoint, preferredTimescale: 600)

        // forwardPlaybackEndTime is intentionally not set here;
        // the boundary time observer handles stop/loop at outPoint.

        Task {
            // Exact seek is required to prevent snapping to the start of compressed audio files.
            let _ = await player.seek(to: inTime, toleranceBefore: .zero, toleranceAfter: .zero)

            // Ensure the user hasn't selected another segment while seeking.
            guard self.playingSegmentID == segment.id else { return }

            player.defaultRate = self.playbackSpeed
            player.play()

            self.addTimeObserver(for: segment, player: player, inPoint: inPoint, outPoint: outPoint, inTime: inTime)
        }
    }

    func stopAudio() {
        loopTask?.cancel()
        loopTask = nil
        isSchedulingLoop = false

        if let observer = timeObserver {
            audioPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
        audioPlayer?.pause()
        audioPlayer = nil
        playingSegmentID = nil
    }

    func openFile() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
#endif
    }

    func load(_ url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let records = try JSONDecoder().decode([SegmentRecord].self, from: data)
            UserDefaults.standard.set(url.path, forKey: Self.lastURLKey)
            fileURL = url
            segments = records.enumerated().map { index, record in
                ReaderSegment(number: index + 1, record: record)
            }
            errorText = nil
            statusText = "Loaded \(segments.count) segments"
            stopAudio()
        } catch {
            errorText = error.localizedDescription
            statusText = "Could not load JSON"
        }
    }

    func restoreLastURL() {
        guard !isNotEmptySegments,
              let path = UserDefaults.standard.string(forKey: Self.lastURLKey),
              !path.isEmpty else { return }
        load(URL(fileURLWithPath: path))
    }

    // MARK: - Private playback helpers

private func restartPlaybackIfNeeded() {
    // If a segment is currently playing, restart playback to apply new settings.
    guard let currentID = playingSegmentID,
          let segment = segments.first(where: { $0.id == currentID }) else { return }
    // Preserve current playback speed.
    let currentSpeed = playbackSpeed
    // Stop existing playback.
    stopAudio()
    // Re‑play the same segment with updated offsets/gap/looping.
    setPlaybackSpeed(currentSpeed)
    playAudio(for: segment)
}

private func addTimeObserver(for segment: ReaderSegment, player: AVPlayer, inPoint: Double, outPoint: Double, inTime: CMTime) {
        // A boundary observer fires during playback the moment the playhead
        // reaches outPoint — before the player can stop — so loop logic runs.
        let outTimeValue = NSValue(time: CMTime(seconds: outPoint, preferredTimescale: 600))
        self.timeObserver = player.addBoundaryTimeObserver(forTimes: [outTimeValue], queue: .main) { [weak self, weak player] in
            Task { @MainActor in
                guard let self = self, let player = player else { return }
                guard self.playingSegmentID == segment.id, !self.isSchedulingLoop else { return }

                if self.isLooping {
                    self.scheduleLoop(for: segment, player: player, inPoint: inPoint, outPoint: outPoint, inTime: inTime)
                } else {
                    self.stopAudio()
                }
            }
        }
    }

    private func scheduleLoop(for segment: ReaderSegment, player: AVPlayer, inPoint: Double, outPoint: Double, inTime: CMTime) {
        self.isSchedulingLoop = true
        player.pause()

        loopTask = Task {
            if self.loopGap > 0 {
                try? await Task.sleep(nanoseconds: UInt64(self.loopGap * 1_000_000_000))
            }
            guard !Task.isCancelled, self.playingSegmentID == segment.id else { return }

            if !self.isLooping {
                self.stopAudio()
                return
            }

            let _ = await player.seek(to: inTime, toleranceBefore: .zero, toleranceAfter: .zero)
            guard !Task.isCancelled, self.playingSegmentID == segment.id else { return }

            self.isSchedulingLoop = false
            player.defaultRate = self.playbackSpeed
            player.play()
        }
    }
}

// MARK: -

struct ReaderSegment: Identifiable, Equatable {
    let number: Int
    let record: SegmentRecord

    var id: Int { number }
}
