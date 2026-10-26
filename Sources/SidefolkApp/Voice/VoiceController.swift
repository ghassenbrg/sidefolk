import AppKit
import AVFoundation
import NaturalLanguage
import SidefolkCore

/// What the voice side needs from the rest of the app.
@MainActor
protocol VoiceHost: AnyObject {
    var ask: AskModel { get }
    var currentSettings: AppSettings { get }
    /// The Ask panel, with the keyboard (for the words as they come, and Esc).
    func showAskForVoice()
    /// The companion's pose follows the microphone: ears up while it is on, thinking while the last
    /// words settle.
    func voiceMood(hearing: Bool, transcribing: Bool)
    /// A brief sad face: nothing usable was heard.
    func voiceMissed()
    /// The companion's mouth: 0...1 while speaking, nil closed.
    func mouth(_ level: Double?)
    /// Cancels the AI run in progress, so no stale answer turns up after an interruption.
    func cancelRun()
}

/// A request whose reply may be said aloud: spoken with the talk key, or typed while replies are
/// always spoken.
struct ReplyContext {
    var spoken: Bool
    var at: Date
    fileprivate var generation: Int
}

/// Push-to-talk and spoken replies (D34). Holding the talk key (or pressing and holding the
/// companion) turns the microphone on; the words appear in the Ask box as they are recognized;
/// releasing sends them through the normal Ask pipeline, with the same cards, approvals and Undo.
/// Replies are said in one short line, unless quiet mode, a call or typing says otherwise, and the
/// talk key, a click on the companion or Esc silences them at once.
@MainActor
final class VoiceController {
    unowned let host: any VoiceHost
    let secrets: any SecretStore
    let player: SpeechPlayer
    private let capture = MicrophoneCapture()
    private var recognizer: (any SpeechRecognizer)?
    /// Opening the microphone and recognizer, then finishing: one step after the other.
    private var work: Task<Void, Never>?
    /// The talk key or the companion is held now.
    private(set) var holding = false
    /// Bumped by every interruption: replies to requests made before it stay silent.
    private var generation = 0
    /// A spoken request is still being worked on (its run can be cancelled by an interruption).
    private var awaitingSpokenReply = false
    private var mouthLevel: Double?
    /// The preferred models this ElevenLabs key may use, listed (free) along with its voices.
    var elevenLabsModels: [String]?

    init(host: any VoiceHost, secrets: any SecretStore, sink: any AudioSink = AudioPlayer()) {
        self.host = host
        self.secrets = secrets
        player = SpeechPlayer(sink: sink)
        player.onLevel = { [weak self] level in self?.moveMouth(level) }
        capture.onLost = { [weak self] in self?.fail(UserFacingError("The microphone went away while you were talking. Nothing was sent.")) }
    }

    var isSpeaking: Bool { player.isSpeaking }
    /// Listening, or finishing what was heard.
    var isActive: Bool { holding || host.ask.voice != nil }

    // MARK: Talking

    /// The talk key went down, or the companion is pressed and held.
    func begin() {
        interrupt(cancelRun: true)
        guard host.currentSettings.voice.input, !holding else { return }
        // A new request replaces one still being worked on, unless that one waits for this answer.
        if host.ask.busy, host.ask.pendingQuestion == nil { host.cancelRun() }
        start(feed: nil)
    }

    /// Released: what was heard goes through the normal Ask pipeline.
    func end() {
        guard holding else { return }
        holding = false
        let opening = work
        work = Task {
            await opening?.value
            capture.stop()
            // Opening failed, Esc was pressed, or the language's model is downloading.
            guard let recognizer, host.ask.voice != nil, host.ask.voice != .finishing else { return finishedTalking() }
            if case .preparing? = host.ask.voice { return finishedTalking() }
            host.ask.voice = .finishing
            host.voiceMood(hearing: false, transcribing: true)
            let heard = await recognizer.finish()
            self.recognizer = nil
            finishedTalking()
            guard host.ask.voice == .finishing else { return }
            host.ask.voice = nil
            await deliver(heard)
        }
    }

    /// Esc: nothing is sent; returns false when there was nothing to cancel or silence.
    @discardableResult
    func cancel() -> Bool {
        if isSpeaking || awaitingSpokenReply {
            interrupt(cancelRun: true)
            return true
        }
        guard isActive else { return false }
        holding = false
        work?.cancel()
        capture.stop()
        let stopping = recognizer
        recognizer = nil
        Task { await stopping?.cancel() }
        host.ask.voice = nil
        host.ask.text = ""
        finishedTalking()
        return true
    }

    /// Silence now: the audio stops and its queue is dropped; with `cancelRun`, the AI run still
    /// working on a spoken request is cancelled too, so its answer never turns up late.
    func interrupt(cancelRun: Bool) {
        generation += 1
        player.stop()
        if cancelRun, awaitingSpokenReply, host.ask.busy, host.ask.pendingQuestion == nil { host.cancelRun() }
        awaitingSpokenReply = false
    }

    private func start(feed file: URL?) {
        holding = true
        host.showAskForVoice()
        host.ask.text = ""
        host.ask.voice = .starting
        // Ears up from the moment the key goes down: the same code opens the microphone.
        host.voiceMood(hearing: true, transcribing: false)
        watchEscape()
        work = Task { await open(file) }
    }

    /// Esc while talking, even with the talk key's modifiers still down (⌘⇧⎋ isn't a cancel to AppKit).
    private var escape: Any?

    private func watchEscape() {
        guard escape == nil else { return }
        escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.isActive || self.isSpeaking else { return event }
            self.cancel()
            return nil
        }
    }

    /// Called whenever talking is over, however it ended.
    private func stopWatchingEscape() {
        escape.map(NSEvent.removeMonitor)
        escape = nil
    }

    private func open(_ file: URL?) async {
        if file == nil {
            let asking = AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
            guard await Self.microphoneAllowed() else {
                return fail(UserFacingError("I can't hear you: Sidefolk isn't allowed to use the microphone. Nothing was sent.",
                                            recovery: "Allow it in System Settings › Privacy & Security › Microphone."))
            }
            // The key was let go to answer macOS's question: nothing was heard yet.
            if asking, !holding {
                host.ask.voice = nil
                notice(.info(String(localized: "The microphone is ready. Hold to talk.")))
                return
            }
        }
        let language = host.currentSettings.voice.language
        do {
            let recognizer = try await Recognition.make(language)
            self.recognizer = recognizer
            try await recognizer.start { [weak self] words in self?.heard(words) }
            guard host.ask.voice == .starting else { return }
            host.ask.voice = .listening(basic: recognizer is BasicRecognizer)
            if let file {
                try await Self.play(file, into: recognizer)
            } else {
                try capture.start(Self.feed(recognizer))
            }
        } catch Recognition.Failure.needsDownload {
            await download(language)
        } catch Recognition.Failure.unsupported {
            fail(UserFacingError("I can't listen in that language on this Mac. Nothing was sent.", recovery: "Pick another one in Settings › Voice."))
        } catch Recognition.Failure.notAllowed {
            fail(UserFacingError("Speech recognition isn't allowed for Sidefolk. Nothing was sent.",
                                 recovery: "Allow it in System Settings › Privacy & Security › Speech Recognition."))
        } catch MicrophoneCapture.Failure.noMicrophone {
            fail(UserFacingError("I can't find a microphone. Nothing was sent."))
        } catch {
            fail(UserFacingError("I couldn't start listening. Nothing was sent.", recovery: "Try again in a moment.",
                                 detail: String(describing: error)))
        }
    }

    /// The first time a language is used, macOS downloads its model; the panel shows how far it is.
    private func download(_ language: String?) async {
        finishedTalking()
        host.ask.voice = .preparing(0)
        do {
            try await Recognition.install(language) { [weak self] fraction in
                guard let self, case .preparing? = self.host.ask.voice else { return }
                self.host.ask.voice = .preparing(fraction)
            }
            guard case .preparing? = host.ask.voice else { return }
            host.ask.voice = nil
            notice(.info(String(localized: "The speech model is ready. Hold to talk again.")))
        } catch {
            fail(UserFacingError("I couldn't download the speech model. Nothing was sent.", recovery: "Check your internet connection and try again.",
                                 detail: String(describing: error)))
        }
    }

    private func heard(_ words: String) {
        guard host.ask.voice != nil, host.ask.voice != .starting else { return }
        host.ask.text = words
    }

    /// Sends what was heard, or says it wasn't caught and leaves it to edit.
    private func deliver(_ heard: String) async {
        guard let words = VoicePolicy.usableTranscript(heard) else { return missed(heard) }
        // A run the talk key cancelled may still be winding down.
        for _ in 0..<20 where host.ask.busy && host.ask.pendingQuestion == nil { try? await Task.sleep(for: .milliseconds(100)) }
        host.ask.text = words
        host.ask.submit(spoken: true)
    }

    private func missed(_ heard: String) {
        host.voiceMissed()
        let words = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        notice(.info(words.isEmpty ? String(localized: "I didn't catch that. Hold to talk again.")
            : String(localized: "I didn't catch that. Fix the words and press Return, or hold to talk again.")))
        host.ask.text = words
        host.ask.focusRequest += 1
    }

    /// Something about talking itself, as a request of its own, so it doesn't read as part of the last answer.
    private func notice(_ content: AskEntry.Content) {
        host.ask.add(content, caption: String(localized: "Talking", comment: "Shown above what the companion says about voice input itself"))
    }

    private func fail(_ error: UserFacingError) {
        holding = false
        capture.stop()
        let stopping = recognizer
        recognizer = nil
        Task { await stopping?.cancel() }
        host.ask.voice = nil
        finishedTalking()
        host.voiceMissed()
        notice(.error(error, retryable: false))
    }

    /// Talking is over, however it ended: the pose and the Esc watch go back.
    private func finishedTalking() {
        host.voiceMood(hearing: false, transcribing: false)
        stopWatchingEscape()
    }

    // MARK: Replies

    /// Called as a request is submitted; its reply is spoken only if nothing interrupted since.
    func context(spoken: Bool) -> ReplyContext {
        if spoken { awaitingSpokenReply = true }
        return ReplyContext(spoken: spoken, at: Date(), generation: generation)
    }

    /// The reply to a request: said aloud when the rules allow it, shown in any case (D34).
    func reply(_ line: String, to context: ReplyContext, in model: AskModel) {
        guard context.generation == generation else { return }
        if context.spoken { awaitingSpokenReply = false }
        let settings = host.currentSettings
        let decision = VoicePolicy.reply(spokenRequest: context.spoken, replies: settings.voice.replies, quiet: settings.isQuiet(at: Date()),
                                         micInUseElsewhere: AudioDevices.inputInUseElsewhere(), typedSince: typedSince(context),
                                         voiceOver: NSWorkspace.shared.isVoiceOverEnabled)
        switch decision {
        case .none:
            return
        case .muted(let why):
            model.add(.spoken(line, muted: why))
        case .announce:
            // VoiceOver reads it in the person's own voice settings, instead of talking over it.
            model.add(.spoken(line, muted: nil))
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: line, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        case .speak:
            model.add(.spoken(line, muted: nil))
            say(line, with: settings.voice) { [weak model] error in
                guard let error, !(error is CancellationError) else { return }
                model?.add(.error(error as? UserFacingError ?? UserFacingError("I couldn't say that out loud. It's on the screen.",
                                                                                 detail: String(describing: error)), retryable: false))
            }
        }
    }

    /// Waits until the companion stops talking (the panel stays up while its words are said).
    func finishedSpeaking() async {
        await player.finished()
    }

    func say(_ line: String, with settings: VoiceSettings, done: (@MainActor (Error?) -> Void)? = nil) {
        guard let engine = engine(for: settings) else {
            done?(UserFacingError("Spoken replies need your ElevenLabs key and a voice.", recovery: "Add them in Settings › Voice."))
            return
        }
        let voice = settings.engine == .apple ? settings.appleVoice : settings.elevenLabsVoice
        let style = VoiceStyle(voice: voice, language: Self.language(of: line), rate: settings.rate)
        player.say(line, with: engine, style: style, volume: Float(settings.volume), done: done)
    }

    func engine(for settings: VoiceSettings) -> (any SpeechOutput)? {
        switch settings.engine {
        case .apple:
            return AppleVoice()
        case .elevenLabs:
            guard !settings.elevenLabsVoice.isEmpty, let key = elevenLabsKey else { return nil }
            return ElevenLabsVoice(client: ElevenLabs(key: key), models: elevenLabsModels ?? ElevenLabs.preferredModels)
        }
    }

    var elevenLabsKey: Secret? {
        try? ProviderKeys(store: secrets).key(account: SecretKey.elevenLabsAPIKey, host: ElevenLabs.host)
    }

    /// The person typed after asking (a key down since the request, or words in the box).
    private func typedSince(_ context: ReplyContext) -> Bool {
        let sinceRequest = Date().timeIntervalSince(context.at)
        return !host.ask.text.isEmpty || EnvironmentMonitor.secondsSinceKey < sinceRequest - 0.25
    }

    /// The line's own language, so a French answer gets a French voice; else the app's.
    static func language(of line: String) -> String {
        NLLanguageRecognizer.dominantLanguage(for: line)?.rawValue ?? AppLanguage.current
    }

    /// A dozen or more levels a second while audio plays: the mouth moves only on a visible change.
    private func moveMouth(_ level: Float?) {
        let next = level.map { (Double($0) * 8).rounded() / 8 }
        guard next != mouthLevel else { return }
        mouthLevel = next
        host.mouth(next)
        #if DEBUG
        // Agents can't watch the mouth: the log says how often it moved for each line.
        mouthMoves += 1
        if next == nil {
            Log.shared.info("voice", "mouth closed", ["moves": String(mouthMoves)])
            mouthMoves = 0
        }
        #endif
    }

    #if DEBUG
    private var mouthMoves = 0
    #endif

    // MARK: Audio plumbing

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Built outside the main actor: the microphone delivers on its own thread.
    nonisolated private static func feed(_ recognizer: any SpeechRecognizer) -> @Sendable (AVAudioPCMBuffer) -> Void {
        { buffer in recognizer.append(buffer) }
    }

    /// An audio file into the recognizer at the pace it was spoken, as if the microphone heard it.
    nonisolated static func play(_ file: URL, into recognizer: any SpeechRecognizer) async throws {
        let audio = try AVAudioFile(forReading: file)
        let format = audio.processingFormat
        let block: AVAudioFrameCount = 4096
        while audio.framePosition < audio.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: block) else { break }
            try audio.read(into: buffer, frameCount: block)
            guard buffer.frameLength > 0 else { break }
            recognizer.append(buffer)
            try await Task.sleep(for: .seconds(Double(buffer.frameLength) / format.sampleRate))
        }
    }

    #if DEBUG
    /// Dev: an audio file plays into the talk pipeline as if the talk key were held for its length
    /// (`swift scripts/dev.swift voice:file:/tmp/x.aiff`). No microphone is opened.
    func talk(file: URL) {
        interrupt(cancelRun: true)
        guard !holding else { return }
        start(feed: file)
        let opening = work
        Task {
            await opening?.value
            end()
        }
    }
    #endif
}
