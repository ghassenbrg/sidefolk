import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// Stands in for api.elevenlabs.io: each path maps to a status and a body, sent in pieces the way a
/// stream arrives. Paths are unique per test (voice ids), so the shared table is safe.
final class ElevenLabsStub: URLProtocol, @unchecked Sendable {
    struct Answer {
        var status = 200
        var pieces: [Data]
    }

    struct Seen {
        var method: String
        var url: URL
        var headers: [String: String]
        var body: JSONValue?
    }

    private static let answers = Mutex<[String: Answer]>([:])
    private static let seen = Mutex<[Seen]>([])

    static func set(_ path: String, _ answer: Answer) { answers.withLock { $0[path] = answer } }
    static func requests(_ path: String) -> [Seen] { seen.withLock { $0.filter { $0.url.path == path } } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var chunk = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&chunk, maxLength: chunk.count)
                if n <= 0 { break }
                data.append(chunk, count: n)
            }
            stream.close()
            body = data
        }
        Self.seen.withLock {
            $0.append(Seen(method: request.httpMethod ?? "GET", url: url, headers: request.allHTTPHeaderFields ?? [:],
                           body: body.flatMap { try? JSONValue.parse($0) }))
        }
        guard let answer = Self.answers.withLock({ $0[url.path] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for piece in answer.pieces { client?.urlProtocol(self, didLoad: piece) }
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite struct ElevenLabsTests {
    let client = ElevenLabs(key: Secret("xi-test-key"), protocolClasses: [ElevenLabsStub.self])

    /// Little-endian 16-bit samples.
    func pcm(_ samples: [Int16]) -> Data {
        var data = Data()
        for s in samples { withUnsafeBytes(of: s.littleEndian) { data.append(contentsOf: $0) } }
        return data
    }

    func json(_ text: String) -> Data { Data(text.utf8) }

    func collect(_ stream: AsyncThrowingStream<VoiceAudio, Error>) async throws -> [Float] {
        var samples: [Float] = []
        for try await piece in stream {
            #expect(piece.sampleRate == 24_000)
            samples += piece.samples
        }
        return samples
    }

    @Test func voicesAreListedByNameWithTheirLabels() async throws {
        ElevenLabsStub.set("/v2/voices", .init(pieces: [json("""
            {"voices": [
              {"voice_id": "v-rowan", "name": "Rowan", "labels": {"gender": "male", "accent": "british"}},
              {"voice_id": "v-juniper", "name": "Juniper", "labels": {"gender": "female", "description": "warm"}},
              {"name": "No id"}
            ], "has_more": false}
            """)]))
        let voices = try await client.voices()
        #expect(voices.map(\.name) == ["Juniper", "Rowan"])
        #expect(voices[0].detail == "female · warm")
        let request = try #require(ElevenLabsStub.requests("/v2/voices").last)
        #expect(request.headers["xi-api-key"] == "xi-test-key")
        #expect(request.url.host == ElevenLabs.host)
    }

    @Test func speechStreamsPCMAsItArrives() async throws {
        // A stream split mid-sample: the decoder keeps the byte order straight.
        let audio = pcm([0, 16_384, -16_384, 32_767])
        ElevenLabsStub.set("/v1/text-to-speech/v-stream/stream", .init(pieces: [audio.prefix(3), audio.dropFirst(3)]))
        let samples = try await collect(client.speech("Saved to Ideas.", voice: "v-stream", models: ["eleven_flash_v2_5"], rate: 1.4,
                                                      language: "fr-FR"))
        #expect(samples == [0, 0.5, -0.5, Float(32_767) / 32_768])
        let request = try #require(ElevenLabsStub.requests("/v1/text-to-speech/v-stream/stream").last)
        #expect(request.method == "POST")
        #expect(request.url.query == "output_format=pcm_24000")
        #expect(request.headers["xi-api-key"] == "xi-test-key")
        #expect(request.body?["text"]?.stringValue == "Saved to Ideas.")
        #expect(request.body?["model_id"]?.stringValue == "eleven_flash_v2_5")
        #expect(request.body?["language_code"]?.stringValue == "fr")
        // ElevenLabs takes 0.7...1.2.
        #expect(request.body?["voice_settings"]?["speed"]?.doubleValue == 1.2)
    }

    @Test func aModelTheEndpointRefusesIsSkippedForTheNext() async throws {
        let path = "/v1/text-to-speech/v-fallback/stream"
        ElevenLabsStub.set(path, .init(status: 422, pieces: [json(#"{"detail": {"status": "invalid_model", "message": "no"}}"#)]))
        await #expect(throws: UserFacingError.self) {
            _ = try await collect(client.speech("Hi.", voice: "v-fallback", models: ["model-a", "model-b"], rate: 1, language: "en"))
        }
        // Both were tried, the first is remembered as refused.
        #expect(ElevenLabsStub.requests(path).compactMap { $0.body?["model_id"]?.stringValue } == ["model-a", "model-b"])
        #expect(ElevenLabs.turnedDown.withLock { $0.contains("model-a") })
        ElevenLabsStub.set(path, .init(pieces: [pcm([100])]))
        _ = try await collect(client.speech("Hi.", voice: "v-fallback", models: ["model-a", "model-b"], rate: 1, language: "en"))
        #expect(ElevenLabsStub.requests(path).last?.body?["model_id"]?.stringValue == "model-b")
    }

    @Test func multilingualV2GetsNoLanguageCode() {
        let request = client.request("Hola.", voice: "v", model: "eleven_multilingual_v2", rate: 1, language: "es-ES")
        let body = request.httpBody.flatMap { try? JSONValue.parse($0) }
        #expect(body?["language_code"] == nil)
        #expect(body?["model_id"]?.stringValue == "eleven_multilingual_v2")
    }

    @Test func failuresSayWhatHappenedAndNothingWasSaid() async throws {
        ElevenLabsStub.set("/v1/text-to-speech/v-badkey/stream", .init(status: 401, pieces: [json(#"{"detail": {"status": "invalid_api_key", "message": "Invalid API key"}}"#)]))
        do {
            _ = try await collect(client.speech("Hi.", voice: "v-badkey", models: ["eleven_flash_v2_5"], rate: 1, language: "en"))
            Issue.record("a refused key must fail")
        } catch let error as UserFacingError {
            #expect(error.message.contains("didn't accept your key"))
            #expect(error.recovery?.contains("Settings › Voice") == true)
        }
        #expect(ElevenLabs.failure(status: 402, body: Data()).message.contains("out of characters"))
        #expect(ElevenLabs.failure(status: 400, body: json(#"{"detail": {"status": "quota_exceeded"}}"#)).message.contains("out of characters"))
        #expect(ElevenLabs.failure(status: 429, body: Data()).message.contains("busy"))
    }

    @Test func theModelsListKeepsThePreferredOnesThatSpeak() async throws {
        ElevenLabsStub.set("/v1/models", .init(pieces: [json("""
            [{"model_id": "eleven_multilingual_v2", "can_do_text_to_speech": true},
             {"model_id": "eleven_flash_v2_5", "can_do_text_to_speech": true},
             {"model_id": "eleven_v4_turbo", "can_do_text_to_speech": false},
             {"model_id": "eleven_english_sts_v2", "can_do_text_to_speech": false}]
            """)]))
        #expect(try await client.models() == ["eleven_flash_v2_5", "eleven_multilingual_v2"])
    }

    @Test func theKeyNeverShowsInDescriptions() {
        let request = client.request("Hi.", voice: "v", model: "m", rate: 1, language: "en")
        #expect(!String(describing: Secret("xi-test-key")).contains("xi-test"))
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "xi-test-key")
    }
}
