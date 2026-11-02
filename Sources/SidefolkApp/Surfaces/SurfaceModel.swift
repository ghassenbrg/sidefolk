import AppKit
import SidefolkCore
import SwiftUI

/// One open surface (D99): the scene on screen, the moves the person makes on it, one at a time and in order, the clocks
/// Sidefolk keeps for it, and the timed sounds and reactions of its animations. Nothing here runs unless a scene asked:
/// with no timer, no `after` and no event left, a surface has no tasks at all.
@MainActor @Observable
final class SurfaceModel {
    let info: SurfaceInfo
    let session: SurfaceSession
    @ObservationIgnored let view = SceneView()
    private(set) var scene: SurfaceScene?
    /// It stopped (no answer, or a scene refused): said in the frame, which then only closes.
    private(set) var failure: String?
    private(set) var canvas = CGSize(width: 240, height: 160)
    private(set) var scale: CGFloat = 1
    var soundsOn: Bool
    /// False while an approval is waiting: nothing of an extension's takes a press meanwhile (T40).
    var takesInput = true {
        didSet { view.takesInput = takesInput }
    }
    /// Who is looking: what lets moves through, and writes rows (T40).
    @ObservationIgnored private var attention = SurfaceAttention()
    var lastActive: Date { attention.lastActive }
    /// It ended for good: `finish` has run.
    @ObservationIgnored var finished = false
    /// What this surface's sounds are read from, to forget them when it goes.
    @ObservationIgnored var reader: PackAssetReader?
    /// The switch among its settings that the speaker is, by its scene or its manifest; nil keeps the choice for the surface.
    private(set) var speakerKey: String?
    @ObservationIgnored var readSpeaker: ((String?) -> Bool?)?
    @ObservationIgnored private var queue: [SurfaceMove] = []
    @ObservationIgnored private var sending = false
    @ObservationIgnored private var timers: [String: (task: Task<Void, Never>, ends: Date)] = [:]
    @ObservationIgnored private var paused: [String: TimeInterval] = [:]
    @ObservationIgnored private var afterTask: Task<Void, Never>?
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var playedRuns: [String: (run: SceneRun, start: Date)] = [:]
    static let maxQueued = 16
    /// A key held down adds nothing while the last press is still on its way: each repeat would only queue.
    var isBusy: Bool { sending || !queue.isEmpty }

    @ObservationIgnored var fitScreen: () -> CGRect = { NSScreen.main?.visibleFrame ?? .zero }
    @ObservationIgnored var onClose: (() -> Void)?
    /// The scene asked to go, or it failed past saving.
    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored var onReact: ((SceneReaction) -> Void)?
    @ObservationIgnored var onSound: ((String) -> Void)?
    @ObservationIgnored var onOver: ((SurfaceScene) -> Void)?
    @ObservationIgnored var onResize: (() -> Void)?
    @ObservationIgnored var reduceMotion: () -> Bool = { SurfaceMotion.reduced }
    @ObservationIgnored var rtl: () -> Bool = { Locale.Language(identifier: AppLanguage.current).characterDirection == .rightToLeft }

    init(info: SurfaceInfo, session: SurfaceSession, soundsOn: Bool) {
        self.info = info
        self.session = session
        self.soundsOn = soundsOn
        speakerKey = info.speakerSetting
        view.onMove = { [weak self] move in self?.send(move) }
        view.onPressSound = { [weak self] path in self?.playSound(path) }
        view.inputOpen = { [weak self] in self?.session.inputOpen() ?? false }
    }

    func open(language: String, arguments: [String: JSONValue]) async {
        do {
            await show(try await session.open(language: language, arguments: arguments))
        } catch {
            fail(error)
        }
    }

    /// The person's move or a clock's: sent in its turn, if the scene on screen still offers it then.
    func send(_ move: SurfaceMove) {
        guard failure == nil, queue.count < Self.maxQueued, attention.admit(move) else { return }
        queue.append(move)
        pump()
    }

    private func pump() {
        guard !sending, !queue.isEmpty else { return }
        sending = true
        let move = queue.removeFirst()
        Task {
            defer {
                sending = false
                pump()
            }
            do {
                // Nil: the scene on screen didn't offer it (a key held down past its moment), and nothing was sent.
                if let next = try await session.move(move) { await show(next) }
            } catch {
                fail(error)
            }
        }
    }

    #if DEBUG
    /// A scene with no extension behind it, for the UI snapshots.
    func showForSnapshot(_ scene: SurfaceScene) async { await show(scene) }
    #endif

    private func show(_ next: SurfaceScene) async {
        for note in next.notes { Log.shared.debug("surfaces", note, ["surface": info.id]) }
        await view.assets.preload(next)
        let screen = fitScreen()
        let wanted = CGSize(width: next.size.width, height: next.size.height)
        let fitted = SurfacePolicy.fit(canvas: wanted, presentation: info.presentation, screen: screen)
        let resized = fitted.size != canvas
        canvas = fitted.size
        scale = fitted.scale
        scene = next
        failure = nil
        view.frame.size = fitted.size
        let still = reduceMotion()
        view.show(next, scale: fitted.scale, rtl: rtl(), reduceMotion: still)
        speakerKey = next.speaker ?? info.speakerSetting
        if let on = readSpeaker?(speakerKey) { soundsOn = on }
        if resized { onResize?() }
        if attention.rowForScene(over: next.over) { onOver?(next) }
        // A reply that came after it was put away is what shows when it comes back; its clocks start then.
        guard !attention.hidden else { return }
        schedule(next, still: still)
        if let words = next.announce { announce(words) }
    }

    /// What the scene needs of time: its clocks (one with the same id carries on), its `after`, its close and its events.
    private func schedule(_ scene: SurfaceScene, still: Bool, events: Bool = true) {
        let ids = Set(scene.timers.map(\.id))
        for (id, running) in timers where !ids.contains(id) {
            running.task.cancel()
            timers[id] = nil
        }
        paused = paused.filter { ids.contains($0.key) }
        for timer in scene.timers where timers[timer.id] == nil { start(timer.id, seconds: paused.removeValue(forKey: timer.id) ?? timer.seconds) }

        afterTask?.cancel()
        afterTask = nil
        if let after = still ? (scene.afterStill ?? scene.after) : scene.after {
            afterTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(after))
                guard !Task.isCancelled else { return }
                self?.send(.next)
            }
        }
        closeTask?.cancel()
        closeTask = nil
        if scene.close {
            let wait = scene.closeAfter
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                self?.onFinished?()
            }
        }
        if events { runEvents(scene, still: still) }
    }

    private func start(_ id: String, seconds: TimeInterval) {
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.timers[id] = nil
            self.send(.timer(id))
        }
        timers[id] = (task, Date().addingTimeInterval(seconds))
    }

    /// Sounds, reactions and announcements at their moments, for the runs that started with this scene, and when moves open.
    private func runEvents(_ scene: SurfaceScene, still: Bool) {
        eventsTask?.cancel()
        eventsTask = nil
        let now = Date()
        var events: [(at: Date, event: SceneEvent)] = []
        var opens = now.addingTimeInterval(scene.inputAfter)
        var fresh: [String: (run: SceneRun, start: Date)] = [:]
        for run in scene.runs {
            let name = run.id ?? ""
            var start = now
            if !name.isEmpty, let played = playedRuns[name], played.run == run {
                start = played.start
            } else {
                // Under Reduce Motion the end of a run that doesn't play shows at once, so what it was building up to comes with it.
                let skipped = still && !run.curves.contains(where: \.essential) && !run.frames.contains(where: \.essential)
                events += run.events.map { (skipped ? start : start.addingTimeInterval($0.at), $0) }
            }
            fresh[name] = (run, start)
            opens = max(opens, start.addingTimeInterval(still ? run.stillBlocks : run.blocks))
        }
        // Events of a run carried on from the last scene are still due, as long as they haven't been played.
        for run in scene.runs {
            guard let name = run.id, let played = playedRuns[name], played.run == run else { continue }
            events += run.events.compactMap { event in
                let at = played.start.addingTimeInterval(event.at)
                return at > now ? (at, event) : nil
            }
        }
        playedRuns = fresh
        session.holdInput(until: opens)
        guard !events.isEmpty else { return }
        events.sort { $0.at < $1.at }
        eventsTask = Task { [weak self] in
            for item in events {
                let wait = item.at.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled, let self else { return }
                if let sound = item.event.sound { self.playSound(sound) }
                if let reaction = item.event.react { self.onReact?(reaction) }
                if let words = item.event.announce { self.announce(words) }
            }
        }
    }

    private func playSound(_ path: String) {
        guard soundsOn, !attention.hidden else { return }
        onSound?(path)
    }

    /// Named, paced and only while it is on screen: VoiceOver is a voice people trust, and its words are the extension's.
    private func announce(_ words: String) {
        guard attention.mayAnnounce() else { return }
        let filled = view.figures.fill(words), name = info.extensionName
        let said = String(localized: "\(name) says: \(filled)", comment: "VoiceOver: what an extension's panel announces, always with the extension's name")
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: said, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    private func fail(_ error: Error) {
        stop()
        failure = (error as? UserFacingError)?.message ?? String(localized: "This stopped.", comment: "An extension's panel ended by itself")
    }

    /// Stops every clock, keeping how long each had left, for coming back. Moves not sent yet are dropped: they were for what was on
    /// screen.
    func pause() {
        attention.hide()
        queue = []
        view.setPaused(true)
        for (id, running) in timers {
            paused[id] = max(running.ends.timeIntervalSinceNow, 0.1)
            running.task.cancel()
        }
        timers = [:]
        afterTask?.cancel()
        eventsTask?.cancel()
    }

    /// Shown again: its clocks go on from where they were, and a scene that was waiting asks for its next.
    func resume() {
        attention.show()
        view.setPaused(false)
        guard let scene else { return }
        schedule(scene, still: reduceMotion(), events: false)
    }

    func stop() {
        pause()
        paused = [:]
        closeTask?.cancel()
    }

    /// Whether what ended now writes its row, once.
    func rowAtEnd() -> Bool { info.activity && attention.rowAtEnd() }
    var writesRows: Bool { info.activity }

    /// A key on the surface: what the scene does with it. True when it took it.
    func press(_ key: String, seat: String?, timestamp: TimeInterval) -> Bool {
        guard let scene, failure == nil, takesInput, let match = SurfacePolicy.match(key, seat: seat, in: scene) else { return false }
        guard session.inputOpen() || match.always else { return false }
        let character: String? = {
            switch match.match {
            case .anyLetter, .anyDigit, .character: key
            case .named: nil
            }
        }()
        if let move = view.press(match, character: character, timestamp: timestamp) { send(move) }
        return true
    }
}

/// The one Activity row a surface leaves, in Sidefolk's words: an extension's own never reach History.
extension SurfaceModel {
    func activityEntry(companionName: String, last: SurfaceScene?) -> ActivityEntry {
        // What it was showing, when its scene says: one surface can hold many things.
        let what = last?.title.map(view.figures.fill) ?? info.title
        var summary = String(localized: "Used \(what) from \(info.extensionName)", comment: "Activity: an extension's panel was used, then whose")
        var args: [String: JSONValue] = ["extension": .string(info.extensionId), "surface": .string(info.surface)]
        if let t = last?.tally {
            summary += " · " + String(localized: "You \(t[0]) · \(companionName) \(t[1])", comment: "A game's score: the person's, then the companion's (named)")
        }
        if let outcome = last?.outcome { args["result"] = .string(outcome.rawValue) }
        return ActivityEntry(at: Date(), caller: "user", tool: "surfaces.use", risk: Risk.low.rawValue, decision: .auto, summary: summary, args: .object(args))
    }
}

/// Whether a surface's steps play. A debug run can ask for Reduce Motion without touching the Mac's settings.
enum SurfaceMotion {
    static var reduced: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SIDEFOLK_REDUCE_MOTION"] == "1" { return true }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
