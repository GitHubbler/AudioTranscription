#if os(macOS)
import AppKit
#endif
import SwiftUI
import UniformTypeIdentifiers

@main
struct SegmentsReaderApp: App {
    var body: some Scene {
        WindowGroup {
            SegmentsReaderView()
        }
#if os(macOS)
        .windowResizability(.contentSize)
#endif
    }
}
