import Foundation

extension WatcherEngine {
    /// One value now, for `watch.read`: the kind's own probe looks once at a watcher that is never added, so
    /// nothing keeps running, nothing is saved and no report slot is taken. Rates are measured over a fresh moment
    /// (`WatchContext.isReadingNow`), and the person's own question isn't made to wait its turn at a site.
    func readNow(_ watcher: Watcher, polite: Bool, within seconds: TimeInterval = 8) async throws -> ProbeResult {
        guard let probe = probes[watcher.kind] else { throw WatchError.unknownKind(watcher.kind) }
        let w = try probe.prepare(watcher)
        for attempt in 1...2 {
            let now = clock.now
            let outcome = await valueWithin(seconds) { () -> Result<ProbeResult, any Error> in
                await WatchContext.$isReadingNow.withValue(true) {
                    await WatchContext.$isManualCheck.withValue(!polite) {
                        do { return .success(try await probe.check(w, now: now)) } catch { return .failure(error) }
                    }
                }
            }
            switch outcome {
            case nil:
                throw UserFacingError("That took too long to answer. Try again in a moment.")
            case .success(let result)?:
                return result
            case .failure(ProbeError.deferred(let until))? where attempt == 1 && until.timeIntervalSince(clock.now) <= 3:
                // Another request went to that site a moment ago: a short wait beats a refusal.
                try await Task.sleep(for: .seconds(max(until.timeIntervalSince(clock.now), 0.1)))
            case .failure(let error)?:
                throw UserFacingError(verbatim: Self.reason(for: error))
            }
        }
        throw UserFacingError(verbatim: ProbeError.deferred(until: clock.now).description)
    }
}

// MARK: watch.read

/// `watch.read`: one value now, the same sources as `watch.report` without anything left running. "What's my CPU
/// usage?" used to make the model start a report and stop it again (D35, amended).
struct WatchReadTool: Tool {
    let engine: WatcherEngine
    /// Where the person is, when they share it: the weather's place when none is named (D48).
    var here: @Sendable () -> KnownPlace? = { nil }

    var spec: ToolSpec {
        ToolSpec(
            name: "watch.read", title: String(localized: "Read a value now"),
            description: """
            Read one value right now and answer with it: this Mac's cpu, memory, battery, disk or network (metric), the \
            weather in a place (built in, no address needed: temperature, feels_like, humidity, wind, precipitation or \
            conditions), or one value on a web page or API (json_path, selector or regex). Use it for "what's my CPU \
            usage", "how much memory am I using", "what's the temperature in Fukuoka". Nothing keeps running; only when the \
            user wants the value again and again is it watch.report.
            """,
            inputSchema: Schema.object([
                "source": Schema.string("What kind of value.", enum: ["metric", "weather", "web"]),
                "metric": Schema.string("metric: which value of this Mac.", enum: Metric.allCases.map(\.rawValue)),
                "place": Schema.string("weather: the place as the user said it, like \"Fukuoka\" or \"Paris, France\". Leave out for where the user is."),
                "quantity": Schema.string("weather: what to read (default temperature).", enum: WeatherQuantity.allCases.map(\.rawValue)),
                "url": Schema.string("web: the page or API address."),
                "json_path": Schema.string("web: a path into a JSON reply, like current.temperature_2m or data[0].price."),
                "selector": Schema.string("web: a simple CSS selector (tag, .class, #id or tag.class) whose text is the value."),
                "regex": Schema.string("web: a regular expression; its first group (or else the whole match) is the value."),
            ], required: ["source"]),
            // The weather and a web value reach a server, so this weighs as a network call wherever that matters.
            risk: .low, capabilities: [.system, .network], category: .watch, mutates: false)
    }

    func summary(for input: JSONValue) -> String {
        String(localized: "Read \(WatchReportTool.title(placed(input)) ?? String(localized: "a value")) now", comment: "“Read CPU now”")
    }

    /// The weather with no place named is the person's own (D48).
    private func placed(_ input: JSONValue) -> JSONValue {
        guard input.string("source") == "weather", input.string("place") == nil, let here = here() else { return input }
        return input.setting("place", .string(here.name))
    }

    /// A web value fetches an address the model may have built: Guard weighs it like any other link (T1, T2).
    func scope(for input: JSONValue) -> ToolScope { WatchReportTool(engine: engine).scope(for: input) }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let source = try Report.source(input, here: here(), context: context) else { return PlaceNeeded.result }
        let (kind, config) = (source.kind, source.config)
        let title = WatchReportTool.title(input.setting("place", config["place"])) ?? String(localized: "Value")
        let watcher = Watcher(kind: kind, title: title, config: config, intervalS: 0, mode: .report,
                              source: WatchSource.string(for: context), now: context.now)
        let found: ProbeResult
        do { found = try await engine.readNow(watcher, polite: context.caller != .user) } catch { throw WatchInput.watchError(error) }
        guard let reading = found.reading else {
            throw UserFacingError("I couldn't read a value there.")
        }
        // The place as the weather service named it ("Fukuoka, Japan"): which Fukuoka it was.
        let place = kind == WatchKind.weather ? found.state.string("place") : nil
        let card = ResultCard(kind: .reading, title: String(localized: "\(title): \(reading.shown.displaySafe.clipped(WatchLimits.readingLimit))",
                                                            comment: "A value read now: “CPU: 23 %”, “Temperature in Fukuoka: 18 °C”"),
                              subtitle: place, url: kind == WatchKind.webValue ? config.string("url") : nil)
        let said = place.map { " (\($0))" } ?? ""
        return ToolResult(text: "\(Self.nameForModel(input.setting("place", config["place"]))) right now\(said): \(reading.forModel). Nothing keeps running.",
                          card: card, untrusted: reading.fromOutside)
    }

    /// What was read, in English for the model: "CPU use", "Temperature in Fukuoka".
    static func nameForModel(_ input: JSONValue) -> String {
        switch input.string("source") {
        case "metric":
            switch input.string("metric").flatMap({ Metric(rawValue: $0.lowercased()) }) {
            case .cpu?: return "CPU use"
            case .memory?: return "Memory in use"
            case .battery?: return "Battery"
            case .disk?: return "Free disk space"
            case .network?: return "Network speed"
            case nil: return "The value"
            }
        case "weather":
            let quantity = (input.string("quantity") ?? "temperature").replacingOccurrences(of: "_", with: " ")
            return "The \(quantity) in \(WeatherProbe.cleanPlace(input.string("place")) ?? "that place")"
        default:
            return "The value"
        }
    }
}
