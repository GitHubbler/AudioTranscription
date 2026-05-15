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

    var isNotEmptySegments: Bool {
        !segments.isEmpty
    }

    private static let lastURLKey = "LastOpenedFileURL"
    private var audioPlayer: AVPlayer?
    private var timeObserver: Any?

    func playAudio(for segment: ReaderSegment) {
        if playingSegmentID == segment.id {
            stopAudio()
            return
        }

        stopAudio()

        guard let inPoint = segment.record.audioInPoint,
              let outPoint = segment.record.audioOutPoint,
              let audioName = segment.record.sourceAudio,
              let jsonURL = fileURL else {
            return
        }

        let audioURL = jsonURL.deletingLastPathComponent().appendingPathComponent(audioName)
        let playerItem = AVPlayerItem(url: audioURL)
        let player = AVPlayer(playerItem: playerItem)
        
        self.audioPlayer = player
        self.playingSegmentID = segment.id
        
        let inTime = CMTime(seconds: inPoint, preferredTimescale: 600)
        let outTime = CMTime(seconds: outPoint, preferredTimescale: 600)
        
        // Natively stops the player at the outPoint
        playerItem.forwardPlaybackEndTime = outTime
        
        Task {
            // Exact seek is required to prevent snapping to the start of compressed audio files
            let _ = await player.seek(to: inTime, toleranceBefore: .zero, toleranceAfter: .zero)
            
            // Ensure the user hasn't selected another segment while seeking
            guard self.playingSegmentID == segment.id else { return }
            
            player.play()
            
            self.timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self, weak player] time in
                Task { @MainActor in
                    guard let self = self, let player = player else { return }
                    
                    // Reset UI if we hit the out point or if playback naturally stopped (rate == 0) after starting
                    if time.seconds >= outPoint || (player.rate == 0 && time.seconds > inPoint + 0.1) {
                        if self.playingSegmentID == segment.id {
                            self.stopAudio()
                        }
                    }
                }
            }
        }
    }

    func stopAudio() {
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
