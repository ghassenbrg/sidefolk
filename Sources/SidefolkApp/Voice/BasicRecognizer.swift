import AVFoundation
import Speech
import Synchronization

/// The older recognizer, forced to stay on this Mac: what macOS 15 has (D34). About four times the
/// errors of SpeechAnalyzer and a one-minute limit, so Settings labels it "basic". Unlike
/// SpeechAnalyzer it needs the speech-recognition permission, asked the first time the person talks.
nonisolated final class BasicRecognizer: SpeechRecognizer, @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private let state = Mutex(State())
    /// Set once by `start`, before any audio arrives; only cancelled afterwards (it is thread-safe).
    nonisolated(unsafe) private var task: SFSpeechRecognitionTask?

    private struct State {
        var latest = ""
        var done: CheckedContinuation<Void, Never>?
        var finished = false
    }

    init?(locale: Locale) {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else { return nil }
        self.recognizer = recognizer
    }

    static func supports(_ locale: Locale) -> Bool {
        SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition == true
    }

    func start(partial: @escaping @MainActor @Sendable (String) -> Void) async throws {
        try await Self.authorize()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let text = result?.bestTranscription.formattedString {
                self.state.withLock { $0.latest = text }
                Task { @MainActor in partial(text) }
            }
            if result?.isFinal == true || error != nil { self.settle() }
        }

    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }

    func finish() async -> String {
        request.endAudio()
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.settle()
        }
        await withCheckedContinuation { continuation in
            let resumeNow = state.withLock { s -> Bool in
                if s.finished { return true }
                s.done = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
        timeout.cancel()
        return state.withLock { $0.latest }.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {
        task?.cancel()
        settle()
    }

    private func settle() {
        let waiting = state.withLock { s -> CheckedContinuation<Void, Never>? in
            s.finished = true
            defer { s.done = nil }
            return s.done
        }
        waiting?.resume()
    }

    /// Asks once, on the person's own press; afterwards the answer stands until System Settings changes it.
    private static func authorize() async throws {
        var status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        guard status == .authorized else { throw Recognition.Failure.notAllowed }
    }
}
