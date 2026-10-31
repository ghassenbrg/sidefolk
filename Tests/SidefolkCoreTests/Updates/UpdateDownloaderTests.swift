import Foundation
import Testing
@testable import SidefolkCore

@Suite struct UpdateDownloaderTests {
    /// A download asked for by a task already cancelled (Settings closed while the gallery's catalog loaded) used to
    /// invalidate its session first and then create a task in it, which raises an exception and quits the app.
    /// It must just stop, and never reach the network.
    @Test func aCancelledTaskStopsWithoutStarting() async {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-download-\(UUID().uuidString)")
        let work = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await UpdateDownloader().download(URL(string: "https://github.com/ghassenbrg/sidefolk/releases/download/none/x.zip")!,
                                                  to: destination, expectedBytes: 10, progress: { _ in })
        }
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
