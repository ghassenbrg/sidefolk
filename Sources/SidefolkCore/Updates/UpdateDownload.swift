import CryptoKit
import Foundation

/// Fetches a release file to disk, reporting the bytes received so far.
public protocol UpdateDownloading: Sendable {
    func download(_ url: URL, to destination: URL, expectedBytes: Int64,
                  progress: @escaping @Sendable (Int64) -> Void) async throws
}

/// The real download: an ephemeral session (no cookies, no cache, no credentials) that follows GitHub's
/// redirect to its file storage and nowhere else, and gives up on a stalled connection.
public struct UpdateDownloader: UpdateDownloading {
    public init() {}

    /// https on github.com or GitHub's file hosts (release-assets / objects .githubusercontent.com).
    static func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".githubusercontent.com")
    }

    public func download(_ url: URL, to destination: URL, expectedBytes: Int64,
                         progress: @escaping @Sendable (Int64) -> Void) async throws {
        guard Self.allowed(url) else { throw UserFacingError("The update's address isn't on GitHub, so Sidefolk didn't fetch it.") }
        let delegate = Delegate(destination: destination, limit: max(expectedBytes, 1) + 1024, progress: progress)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30 * 60
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.setValue("Sidefolk/\(SidefolkVersion.current)", forHTTPHeaderField: "User-Agent")
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.finish = { continuation.resume(with: $0) }
                if !delegate.start({ session.downloadTask(with: request) }) {
                    delegate.finish = nil
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            // Not `session.invalidateAndCancel()`: a task already cancelled runs this before the download starts,
            // and a task created in an invalidated session raises an exception (the app quit when Settings closed
            // while the gallery's catalog was loading).
            delegate.cancel()
        }
    }

    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let destination: URL
        let limit: Int64
        let progress: @Sendable (Int64) -> Void
        var finish: ((Result<Void, Error>) -> Void)?
        private var moved: Result<Void, Error>?
        private var task: URLSessionTask?
        private var cancelled = false
        private let lock = NSLock()

        /// Makes and starts the download unless it was cancelled first; false when it never started.
        func start(_ make: () -> URLSessionTask) -> Bool {
            let started: URLSessionTask? = lock.withLock {
                guard !cancelled else { return nil }
                task = make()
                return task
            }
            started?.resume()
            return started != nil
        }

        /// Stops the download if it started (its delegate then reports it stopped), and keeps one from starting.
        func cancel() {
            let running: URLSessionTask? = lock.withLock {
                cancelled = true
                return task
            }
            running?.cancel()
        }

        init(destination: URL, limit: Int64, progress: @escaping @Sendable (Int64) -> Void) {
            self.destination = destination
            self.limit = limit
            self.progress = progress
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(request.url.map(UpdateDownloader.allowed) == true ? request : nil)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            // A file far larger than the release said is not the one it described.
            if totalBytesWritten > limit { downloadTask.cancel() }
            progress(totalBytesWritten)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            let result: Result<Void, Error>
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                result = .failure(UserFacingError("GitHub didn't hand over the update (status \(http.statusCode))."))
            } else {
                // The temporary file is gone once this returns, so it is moved now.
                result = Result {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: location, to: destination)
                }
            }
            lock.withLock { moved = result }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let outcome: Result<Void, Error> = lock.withLock {
                if let error {
                    return (error as? URLError)?.code == .cancelled
                        ? .failure(UserFacingError("The download stopped before it finished."))
                        : .failure(UserFacingError("Sidefolk couldn't download the update.", recovery: "Check the connection and try again.",
                                                   detail: error.localizedDescription))
                }
                return moved ?? .failure(UserFacingError("Sidefolk couldn't download the update."))
            }
            finish?(outcome)
            finish = nil
        }
    }
}

/// A file's SHA-256, read in pieces so a large disk image never sits in memory whole.
public enum FileDigest {
    public static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The hex digest in a `shasum -a 256` line ("<hex>  <name>"), if it names `file` (or no file at all).
    public static func parse(_ text: String, for file: String) -> String? {
        let parts = text.split(whereSeparator: \.isWhitespace)
        guard let hex = parts.first.map({ $0.lowercased() }), hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        if parts.count >= 2, parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "*")) != file { return nil }
        return hex
    }
}
