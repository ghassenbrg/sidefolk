import Foundation
import Synchronization

/// ElevenLabs text to speech with the person's own key (D34). Listing voices and models is free;
/// speaking costs characters on their plan. Requests go to api.elevenlabs.io only and are never
/// redirected, so the key can't be replayed elsewhere. What is sent: the words being said.
public struct ElevenLabs: Sendable {
    public static let host = "api.elevenlabs.io"
    /// Most natural first, all of them fast enough to stream. A model the endpoint turns down is
    /// skipped for the next, so a model ElevenLabs retires doesn't silence the companion.
    public static let preferredModels = ["eleven_v4_turbo", "eleven_flash_v2_5", "eleven_multilingual_v2"]
    /// 16-bit mono PCM: plays without a decoder and can start on the first bytes.
    static let sampleRate = 24_000.0
    /// Bytes per piece handed to the player: a tenth of a second.
    static let pieceBytes = 4_800

    public struct Voice: Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String
        /// "female · American · warm", from the voice's labels.
        public var detail: String

        public init(id: String, name: String, detail: String) {
            self.id = id
            self.name = name
            self.detail = detail
        }
    }

    private let key: Secret
    private let session: URLSession
    private let base = URL(string: "https://\(ElevenLabs.host)")!

    public init(key: Secret) {
        self.init(key: key, protocolClasses: [])
    }

    /// Test seam: route requests through stub `URLProtocol`s instead of the network.
    init(key: Secret, protocolClasses: [AnyClass]) {
        self.key = key
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 20
        if !protocolClasses.isEmpty { config.protocolClasses = protocolClasses + (config.protocolClasses ?? []) }
        session = URLSession(configuration: config)
    }

    // MARK: Listing (free)

    /// The voices in the person's ElevenLabs library, by name.
    public func voices() async throws -> [Voice] {
        var voices: [Voice] = []
        var token: String?
        // Three pages of a hundred cover any library a person picks a voice from.
        for _ in 0..<3 {
            var components = URLComponents(url: base.appendingPathComponent("v2/voices"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "page_size", value: "100")] + (token.map { [URLQueryItem(name: "next_page_token", value: $0)] } ?? [])
            let json = try await get(components.url!)
            for voice in json["voices"]?.arrayValue ?? [] {
                guard let id = voice.string("voice_id"), let name = voice.string("name") else { continue }
                let labels = voice["labels"]
                let detail = ["gender", "accent", "description"].compactMap { labels?.string($0) }.joined(separator: " · ")
                voices.append(Voice(id: id, name: name, detail: detail))
            }
            guard json["has_more"]?.boolValue == true, let next = json.string("next_page_token") else { break }
            token = next
        }
        return voices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The preferred models this key can use for speech, best first.
    public func models() async throws -> [String] {
        let json = try await get(base.appendingPathComponent("v1/models"))
        let available = Set((json.arrayValue ?? []).filter { $0["can_do_text_to_speech"]?.boolValue != false }.compactMap { $0.string("model_id") })
        let preferred = Self.preferredModels.filter(available.contains)
        return preferred.isEmpty ? Array(Self.preferredModels.dropFirst()) : preferred
    }

    private func get(_ url: URL) async throws -> JSONValue {
        var request = URLRequest(url: url)
        request.setValue(key.reveal(), forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request, delegate: NoRedirects.shared)
        } catch {
            throw Self.networkError(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Self.failure(status: status, body: data) }
        do { return try JSONValue.parse(data) } catch {
            throw UserFacingError("ElevenLabs sent something I couldn't read. Nothing was changed.", detail: String(describing: error))
        }
    }

    // MARK: Speaking (costs characters)

    /// `text` said by `voice`, streamed as it is made. Tries `models` in order until one is accepted.
    public func speech(_ text: String, voice: String, models: [String], rate: Double, language: String) -> AsyncThrowingStream<VoiceAudio, Error> {
        let session = self.session
        // Models turned down earlier in this session aren't tried again (the last one always is).
        let skipped = Self.turnedDown.withLock { $0 }
        let usable = models.filter { !skipped.contains($0) }
        let tried = usable.isEmpty ? Array(models.suffix(1)) : usable
        let requests = tried.map { (model: $0, request: request(text, voice: voice, model: $0, rate: rate, language: language)) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for (index, attempt) in requests.enumerated() {
                        do {
                            try await Self.stream(attempt.request, session: session, into: continuation)
                            continuation.finish()
                            return
                        } catch ModelRejected.rejected(let error) where index < requests.count - 1 {
                            Self.turnedDown.withLock { _ = $0.insert(attempt.model) }
                            Log.shared.info("voice", "ElevenLabs turned down a model; trying the next", ["detail": error.detail ?? ""])
                        } catch ModelRejected.rejected(let error) {
                            throw error
                        }
                    }
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? CancellationError() : error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func request(_ text: String, voice: String, model: String, rate: Double, language: String) -> URLRequest {
        var components = URLComponents(url: base.appendingPathComponent("v1/text-to-speech/\(voice)/stream"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "output_format", value: "pcm_24000")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(key.reveal(), forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: JSONValue] = [
            "text": .string(text),
            "model_id": .string(model),
            // ElevenLabs takes 0.7...1.2.
            "voice_settings": ["stability": .number(0.5), "similarity_boost": .number(0.75), "speed": .number(min(max(rate, 0.7), 1.2))],
        ]
        // Multilingual v2 refuses a language code; the newer models use it to avoid guessing.
        let code = String(language.prefix { $0 != "-" && $0 != "_" }).lowercased()
        if model != "eleven_multilingual_v2", code.count == 2 { body["language_code"] = .string(code) }
        request.httpBody = try? JSONEncoder().encode(JSONValue.object(body))
        return request
    }

    private enum ModelRejected: Error { case rejected(UserFacingError) }
    static let turnedDown = Mutex<Set<String>>([])

    private static func stream(_ request: URLRequest, session: URLSession,
                               into continuation: AsyncThrowingStream<VoiceAudio, Error>.Continuation) async throws {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request, delegate: NoRedirects.shared)
        } catch {
            throw networkError(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var body = Data()
            for try await byte in bytes where body.count < 8_192 { body.append(byte) }
            let error = failure(status: status, body: body)
            // Before any audio, a refused model is worth another try with the next one.
            if [400, 404, 422].contains(status) { throw ModelRejected.rejected(error) }
            throw error
        }
        var piece = Data()
        piece.reserveCapacity(pieceBytes)
        do {
            for try await byte in bytes {
                piece.append(byte)
                guard piece.count >= pieceBytes else { continue }
                continuation.yield(decode(piece))
                piece.removeAll(keepingCapacity: true)
            }
        } catch {
            throw networkError(error)
        }
        if piece.count >= 2 { continuation.yield(decode(piece)) }
    }

    /// Little-endian 16-bit samples to floats; an odd last byte waits for the next piece (it never comes: dropped).
    static func decode(_ data: Data) -> VoiceAudio {
        var samples = [Float](repeating: 0, count: data.count / 2)
        data.withUnsafeBytes { raw in
            for i in samples.indices {
                let value = Int16(bitPattern: UInt16(raw[2 * i]) | UInt16(raw[2 * i + 1]) << 8)
                samples[i] = Float(value) / 32_768
            }
        }
        return VoiceAudio(samples: samples, sampleRate: sampleRate)
    }

    // MARK: Errors

    static func failure(status: Int, body: Data) -> UserFacingError {
        let json = try? JSONValue.parse(body)
        let detail = json?["detail"]
        let code = detail?.string("status") ?? ""
        let message = detail?.string("message") ?? detail?.stringValue ?? ""
        let info = Redactor.redact("HTTP \(status) \(code) \(message)").clipped(300)
        switch status {
        case 401:
            return UserFacingError("ElevenLabs didn't accept your key. Nothing was said.",
                                   recovery: "Check the key in Settings › Voice.", detail: info)
        case 402:
            return UserFacingError("Your ElevenLabs plan is out of characters. Nothing was said.",
                                   recovery: "Add characters on elevenlabs.io, or choose Apple's voice in Settings › Voice.", detail: info)
        case 429:
            return UserFacingError("ElevenLabs is busy right now. Nothing was said.", recovery: "Try again in a moment.", detail: info)
        default:
            if code.contains("quota") {
                return UserFacingError("Your ElevenLabs plan is out of characters. Nothing was said.",
                                       recovery: "Add characters on elevenlabs.io, or choose Apple's voice in Settings › Voice.", detail: info)
            }
            if code.contains("voice_not_found") || status == 404 {
                return UserFacingError("ElevenLabs couldn't find that voice. Nothing was said.",
                                       recovery: "Pick another voice in Settings › Voice.", detail: info)
            }
            return UserFacingError("ElevenLabs couldn't make the voice. Nothing was said.", recovery: "Try again in a moment.", detail: info)
        }
    }

    static func networkError(_ error: Error) -> Error {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return CancellationError() }
        if let error = error as? UserFacingError { return error }
        return UserFacingError("I couldn't reach ElevenLabs. Nothing was said.", recovery: "Check your internet connection.",
                               detail: String(describing: error))
    }
}

/// ElevenLabs as one of the engines behind `SpeechOutput`.
public struct ElevenLabsVoice: SpeechOutput {
    let client: ElevenLabs
    let models: [String]

    public init(client: ElevenLabs, models: [String] = ElevenLabs.preferredModels) {
        self.client = client
        self.models = models.isEmpty ? ElevenLabs.preferredModels : models
    }

    public func audio(for sentence: String, style: VoiceStyle) -> AsyncThrowingStream<VoiceAudio, Error> {
        client.speech(sentence, voice: style.voice, models: models, rate: style.rate, language: style.language)
    }
}
