#if os(macOS)
import AppKit
#endif
import SwiftUI
import AVFoundation

@MainActor
final class SegmentsReaderModel: ObservableObject {
    @Published private(set) var fileURL: URL?
    @Published private(set) var segments: [ReaderSegment] = []
    @Published private(set) var statusText = "Open segmented JSON"
    @Published private(set) var errorText: String?
    @Published private(set) var playingSegmentID: Int?
    
    @Published var playbackSpeed: Float = 1.0 {
        didSet {
            if let player = audioPlayer {
                player.defaultRate = playbackSpeed
                if player.rate > 0 {
                    player.rate = playbackSpeed
                }
            }
        }
    }
    
    @Published var isLooping: Bool = false
    @Published var loopGap: TimeInterval = 0.0

    /// Seconds added to every segment's in/out points at playback time.
    /// Compensates for leading silence in the audio source. Default is 0.
    @Published var timeOffset: Double = 0.0

    var isNotEmptySegments: Bool {
        !segments.isEmpty
    }

    private static let lastURLKey = "LastOpenedFileURL"
    private var audioPlayer: AVPlayer?
    private var timeObserver: Any?
    private var loopTask: Task<Void, Never>?
    private var isSchedulingLoop = false

    func playAudio(for segment: ReaderSegment) {
        if playingSegmentID == segment.id {
            stopAudio()
            return
        }

        stopAudio()

        guard let rawInPoint = segment.record.audioInPoint,
              let rawOutPoint = segment.record.audioOutPoint,
              let audioName = segment.record.sourceAudio,
              let jsonURL = fileURL else {
            return
        }

        // Apply the calibration offset; clamp in-point to ≥ 0.
        let inPoint  = max(0, rawInPoint  + timeOffset)
        let outPoint = max(inPoint + 0.01, rawOutPoint + timeOffset)

        let audioURL = jsonURL.deletingLastPathComponent().appendingPathComponent(audioName)
        let playerItem = AVPlayerItem(url: audioURL)
        let player = AVPlayer(playerItem: playerItem)
        
        self.audioPlayer = player
        self.playingSegmentID = segment.id
        
        let inTime = CMTime(seconds: inPoint, preferredTimescale: 600)

        // forwardPlaybackEndTime is intentionally not set here;
        // the boundary time observer handles stop/loop at outPoint.
        
        Task {
            // Exact seek is required to prevent snapping to the start of compressed audio files
            let _ = await player.seek(to: inTime, toleranceBefore: .zero, toleranceAfter: .zero)
            
            // Ensure the user hasn't selected another segment while seeking
            guard self.playingSegmentID == segment.id else { return }
            
            player.defaultRate = self.playbackSpeed
            player.play()
            
            self.addTimeObserver(for: segment, player: player, inPoint: inPoint, outPoint: outPoint, inTime: inTime)
        }
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
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

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
        let url = URL(fileURLWithPath: path)
        load(url)
    }
}

struct ReaderSegment: Identifiable, Equatable {
    let number: Int
    let record: SegmentRecord

    var id: Int { number }
}
