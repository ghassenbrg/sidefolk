import KeyboardShortcuts
import SidefolkCore
import SwiftUI

/// Settings › Voice (D34): talking instead of typing, when the companion answers aloud, and the
/// voice it answers in, each engine saying plainly what it sends and where.
struct VoiceSettingsView: View {
    var model: SettingsModel

    private var voice: VoiceSettingsModel { model.voice }
    private var settings: VoiceSettings { voice.settings }
    private var name: String { voice.companionName }

    var body: some View {
        SettingsPage {
            SettingsGroup(title: "Talking", footer: "The microphone is on only while you hold the shortcut, and what you say is understood on this Mac. The recording is never kept; the words join your requests like typed ones.") {
                SettingsToggle(title: "Voice input", detail: "Hold the shortcut and talk, release to send. Esc cancels.",
                               isOn: Binding(get: { settings.input }, set: { voice.setInput($0) }))
                if settings.input {
                    talkRows
                    MicrophoneRow(voice: voice)
                    LanguageRow(voice: voice)
                }
            }

            SettingsGroup(title: "Spoken replies", footer: "What \(name) says is always shown on screen too. Quiet mode keeps \(name) silent, and so does a call or typing again.") {
                ChoiceRow(title: "Off", detail: "Replies stay on screen.", selected: settings.replies == .off) { voice.update { $0.replies = .off } }
                ChoiceRow(title: "Only when I spoke", detail: "A short spoken answer to what you said aloud. Typed requests get text.",
                          selected: settings.replies == .whenSpoken) { voice.update { $0.replies = .whenSpoken } }
                ChoiceRow(title: "Always", detail: "Typed requests get a spoken answer too.",
                          selected: settings.replies == .always) { voice.update { $0.replies = .always } }
                SettingsRow(title: Text("How much to say"),
                            detail: settings.length == .brief ? Text("One short line: the gist, or how many things and the first.")
                                : Text("The whole answer, up to about two minutes.")) {
                    Picker("How much to say", selection: Binding(get: { settings.length }, set: { l in voice.update { $0.length = l } })) {
                        Text("Briefly").tag(SpokenLength.brief)
                        Text("Everything").tag(SpokenLength.full)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .disabled(settings.replies == .off)
            }

            SettingsGroup(title: "Voice", footer: "An AI voice. \(name) never reads out links, file paths or code.") {
                EngineOption(engine: .apple, voice: voice)
                EngineOption(engine: .elevenLabs, voice: voice)
                SettingsRow(title: Text("Speed"), detail: Text(verbatim: settings.rate.formatted(.number.precision(.fractionLength(2))) + "×")) {
                    Slider(value: Binding(get: { settings.rate }, set: { r in voice.update { $0.rate = (r * 20).rounded() / 20 } }),
                           in: VoiceSettings.rates)
                        .frame(width: 200).accessibilityLabel("Speed")
                }
                SettingsRow(title: "Volume") {
                    Slider(value: Binding(get: { settings.volume }, set: { v in voice.update { $0.volume = v } }), in: 0...1)
                        .frame(width: 200).accessibilityLabel("Volume")
                }
                TestVoiceRow(voice: voice)
            }
        }
    }

    @ViewBuilder private var talkRows: some View {
        SettingsRow(title: Text("Talk with"), detail: settings.talkKey == .askShortcut
                    ? Text("Tap \(askShortcut) to open the Ask panel, hold it to talk. You can also press and hold \(name).")
                    : Text("Hold your talk shortcut. You can also press and hold \(name).")) {
            Picker("Talk with", selection: Binding(get: { settings.talkKey }, set: { key in voice.update { $0.talkKey = key } })) {
                Text("Hold the Ask shortcut").tag(TalkKey.askShortcut)
                Text("Its own shortcut").tag(TalkKey.ownShortcut)
            }
            .labelsHidden()
            .fixedSize()
        }
        if settings.talkKey == .ownShortcut {
            SettingsRow(title: "Talk shortcut", detail: "The microphone opens the moment you press it.") {
                KeyboardShortcuts.Recorder(for: .talk) { _ in model.services.settingsChanged() }
                    .accessibilityLabel("Talk shortcut")
            }
        }
    }

    private var askShortcut: String {
        KeyboardShortcuts.getShortcut(for: .ask)?.description ?? "⌘⇧Space"
    }
}

/// Whether the microphone may be used; never asks from here (the first press does).
private struct MicrophoneRow: View {
    var voice: VoiceSettingsModel

    var body: some View {
        switch voice.microphone {
        case .allowed:
            SettingsRow(title: "Microphone", detail: "Allowed. It prefers the Mac's own microphone.") {
                Chip("Allowed", tone: .success, systemImage: "checkmark")
            }
        case .notAsked:
            SettingsRow(title: "Microphone", detail: "macOS asks the first time you hold the shortcut.") {
                Chip("Not asked yet", tone: .neutral, systemImage: "mic")
            }
        case .denied:
            SettingsRow(title: "Microphone", detail: "Not allowed. Voice input can't hear you until it is.") {
                Button("Open System Settings") { voice.openMicrophoneSettings() }.buttonStyle(.sf(.primary))
            }
        }
    }
}

/// The language to listen in, and whether its speech model is on this Mac.
private struct LanguageRow: View {
    var voice: VoiceSettingsModel

    var body: some View {
        SettingsRow(title: "Language", detail: "Requests are understood in English without AI; with AI, in any language.") {
            Picker("Language", selection: Binding(get: { voice.settings.language ?? "" }, set: { voice.setLanguage($0.isEmpty ? nil : $0) })) {
                Text("Same as Sidefolk (\(AppLanguage.name(of: AppLanguage.current)))").tag("")
                Divider()
                ForEach(voice.languages) { Text(verbatim: $0.name).tag($0.id) }
                if let chosen = voice.settings.language, !voice.languages.contains(where: { $0.id == chosen }) {
                    Text(verbatim: chosen).tag(chosen)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)
        }
        SettingsRow(title: Text("Speech model"), detail: modelDetail) { modelControl }
        if let error = voice.downloadError {
            InlineError(error: error).padding(.horizontal, Theme.Space.l).padding(.bottom, Theme.Space.s)
        }
    }

    private var modelDetail: Text {
        if voice.downloading != nil { return Text("macOS is downloading it into its own storage, not into Sidefolk.") }
        switch voice.recognition {
        case .ready(.basic): return Text("Basic: macOS 15's older recognizer, on this Mac. It makes more mistakes; macOS 26 brings a better one.")
        case .ready(.dictation): return Text("On this Mac, with Apple's dictation model.")
        case .ready: return Text("On this Mac, with Apple's speech model. Nothing you say leaves it.")
        case .needsDownload: return Text("macOS needs to download this language's speech model once. It goes into the system's storage.")
        case .unsupported: return Text("This Mac can't listen in this language. Pick another one.")
        case nil: return Text("Checking…")
        }
    }

    @ViewBuilder private var modelControl: some View {
        if let progress = voice.downloading {
            ProgressView(value: progress).frame(width: 120).accessibilityLabel("Downloading the speech model")
        } else {
            switch voice.recognition {
            case .ready(.basic): Chip("Basic", tone: .warning, systemImage: "waveform")
            case .ready: Chip("Ready", tone: .success, systemImage: "checkmark")
            case .needsDownload: Button("Download") { Task { await voice.download() } }.buttonStyle(.sf(.primary))
            case .unsupported: Chip("Not available", tone: .danger, systemImage: "xmark")
            case nil: ProgressView().controlSize(.small)
            }
        }
    }
}

/// One engine: a radio row, and when chosen, its voices and what it sends.
private struct EngineOption: View {
    var engine: VoiceEngine
    var voice: VoiceSettingsModel

    private var selected: Bool { voice.settings.engine == engine }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch engine {
            case .apple:
                ChoiceRow(title: "Apple voices", detail: "Made on this Mac. Nothing is sent anywhere.", selected: selected) { voice.setEngine(.apple) }
            case .elevenLabs:
                ChoiceRow(title: "ElevenLabs", detail: "Natural voices in many languages, with your own ElevenLabs key.", selected: selected) {
                    voice.setEngine(.elevenLabs)
                }
            }
            if selected {
                VStack(alignment: .leading, spacing: Theme.Space.s) { setup }
                    .padding(.leading, Theme.Space.l + 16 + Theme.Space.m)
                    .padding(.trailing, Theme.Space.l)
                    .padding(.bottom, Theme.Space.m)
            }
        }
    }

    @ViewBuilder private var setup: some View {
        switch engine {
        case .apple: AppleSetup(voice: voice)
        case .elevenLabs: ElevenLabsSetup(voice: voice)
        }
    }
}

private struct AppleSetup: View {
    var voice: VoiceSettingsModel

    var body: some View {
        let voices = voice.appleVoices
        let best = voices.first
        SetupLine(title: "Voice") {
            Picker("Voice", selection: Binding(get: { voice.settings.appleVoice }, set: { id in voice.update { $0.appleVoice = id } })) {
                (best.map { Text("Best installed (\($0.name))") } ?? Text("System voice")).tag("")
                Divider()
                ForEach(voices) { v in Text(verbatim: "\(v.name) · \(qualityName(v.quality))").tag(v.id) }
            }
            .labelsHidden()
            .frame(maxWidth: 240)
        }
        if (best?.quality ?? .compact) < .enhanced {
            Label("Only compact voices are installed, and they sound robotic. Download an enhanced or premium voice for a warmer one.",
                  systemImage: "info.circle")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: Theme.Space.s) {
            Button("Get better voices…") { voice.openSystemVoices() }.buttonStyle(.sf(.secondary))
            Text("System Settings › Accessibility › Spoken Content › System voice › Manage Voices")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func qualityName(_ quality: AppleVoiceChoice.Quality) -> String {
        switch quality {
        case .premium: String(localized: "Premium", comment: "An Apple voice's quality")
        case .enhanced: String(localized: "Enhanced", comment: "An Apple voice's quality")
        case .compact: String(localized: "Compact", comment: "An Apple voice's quality")
        }
    }
}

private struct ElevenLabsSetup: View {
    var voice: VoiceSettingsModel
    @State private var draft = ""

    var body: some View {
        Label("Sends the words \(voice.companionName) says to ElevenLabs (api.elevenlabs.io), with your key: reminders and notes it reads back too. ElevenLabs keeps a history of requests unless your plan turns that off.",
              systemImage: "arrow.up.forward.circle")
            .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
        if voice.hasKey {
            SetupLine(title: "API key") {
                HStack(spacing: Theme.Space.s) {
                    Chip("Saved", tone: .success, systemImage: "key.fill")
                    Button("Remove key") { voice.removeKey() }.buttonStyle(.sf(.destructive))
                }
            }
            SetupLine(title: "Voice") { voicePicker }
            if let error = voice.elevenError { InlineError(error: error) }
        } else {
            SetupLine(title: "API key") {
                HStack(spacing: Theme.Space.s) {
                    SecureField("API key", text: $draft, prompt: Text("Paste key"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                        .onSubmit(save)
                    Button("Save key", action: save)
                        .buttonStyle(.sf(.primary))
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Text("Saved in your Keychain. Listing voices is free; each spoken line uses characters of your ElevenLabs plan.")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var voicePicker: some View {
        if let voices = voice.elevenVoices {
            Picker("Voice", selection: Binding(get: { voice.settings.elevenLabsVoice }, set: { id in
                if let chosen = voices.first(where: { $0.id == id }) { voice.chooseElevenVoice(chosen) }
            })) {
                if voice.settings.elevenLabsVoice.isEmpty { Text("Choose a voice").tag("") }
                ForEach(voices) { v in Text(verbatim: v.detail.isEmpty ? v.name : "\(v.name) · \(v.detail)").tag(v.id) }
                if !voice.settings.elevenLabsVoice.isEmpty, !voices.contains(where: { $0.id == voice.settings.elevenLabsVoice }) {
                    Text(verbatim: voice.settings.elevenLabsVoiceName).tag(voice.settings.elevenLabsVoice)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 260)
        } else if voice.loadingVoices {
            ProgressView().controlSize(.small)
        } else {
            Button("Load voices") { Task { await voice.loadVoices() } }.buttonStyle(.sf(.secondary))
        }
    }

    private func save() {
        voice.saveKey(draft)
        draft = ""
    }
}

/// Says one sentence with the current settings, only when clicked.
private struct TestVoiceRow: View {
    var voice: VoiceSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SettingsRow(title: "Test voice", detail: detail) {
                Button(voice.testing ? "Speaking…" : "Test voice") { Task { await voice.test() } }
                    .buttonStyle(.sf(.secondary))
                    .disabled(voice.testing)
            }
            if let failure = voice.testFailure {
                InlineError(error: failure).padding(.horizontal, Theme.Space.l).padding(.bottom, Theme.Space.s)
            }
        }
    }

    private var detail: LocalizedStringKey {
        voice.settings.engine == .elevenLabs ? "Says one short sentence. It uses about 50 characters of your ElevenLabs plan."
            : "Says one short sentence."
    }
}

/// A labelled control inside an engine's setup.
private struct SetupLine<Control: View>: View {
    var title: LocalizedStringKey
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Text(title).font(Theme.Font.body).foregroundStyle(Theme.ink)
            Spacer(minLength: Theme.Space.s)
            control
        }
    }
}
