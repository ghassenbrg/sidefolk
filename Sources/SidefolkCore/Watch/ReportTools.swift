import Foundation

/// What every report shares: its options, its end, and how a new one is described.
enum Report {
    /// The options any report keeps whatever it reads: a notification each time, no end of its own.
    static func options(of config: JSONValue) -> JSONValue {
        var o: [String: JSONValue] = [:]
        if config["notify"]?.boolValue == true { o["notify"] = true }
        if config["until_stopped"]?.boolValue == true { o["until_stopped"] = true }
        return .object(o)
    }

    static func memory(_ count: Int64) -> String { count.formatted(ByteCountFormatStyle(style: .memory, locale: Wording.locale)) }

    /// Reads "every N seconds" from a tool input: `every_seconds`, or `interval_minutes` as the other watch tools take it.
    static func interval(_ input: JSONValue) throws -> TimeInterval {
        let seconds = input["every_seconds"]?.doubleValue ?? input["interval_minutes"]?.doubleValue.map { $0 * 60 }
        guard let seconds else { return 0 }
        guard seconds > 0, seconds <= WatchLimits.maxInterval else {
            throw ToolError.invalidInput(String(localized: "“every_seconds” must be more than 0 and at most 7 days."))
        }
        return seconds
    }

    /// The end the person gave ("6pm", "in 2 hours", "until tomorrow"), at most 30 days away.
    static func end(_ input: JSONValue, now: Date, parser: WhenParser) throws -> Date? {
        guard var text = input.string("until") else { return nil }
        for lead in ["until ", "till ", "til "] where text.lowercased().hasPrefix(lead) { text = String(text.dropFirst(lead.count)) }
        guard let found = parser.parse(text, now: now) ?? parser.parse("in " + text, now: now), found.recurrence == nil,
              found.confidence != .low, found.date > now else {
            throw ToolError.invalidInput(String(localized: "I couldn't read “\(text.clipped(40))” as a time to stop."))
        }
        return min(found.date, now.addingTimeInterval(WatchLimits.repeatExpiry))
    }

    /// The card and the model's text for a report that just started, with its first value, when it stops, and whether
    /// the interval had to be raised to the floor.
    static func started(_ w: Watcher, requested: TimeInterval, look: FirstLook, engine: WatcherEngine, now: Date) -> ToolResult {
        let every = WatchWords.every(w.intervalS)
        let everyForModel = WatchWords.everyForModel(w.intervalS)
        var text = "Showing \(w.title) every \(everyForModel), live beside the companion"
        var lines: [String] = []
        if let reading = look.reading {
            text += "; it reads \(reading.forModel) now"
        } else if let problem = look.problem ?? look.note {
            text += "; the first reading failed (\(problem.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))), I'll keep trying"
            lines.append(problem)
        }
        text += "."
        if requested > 0, w.intervalS > requested {
            text += " Every \(WatchWords.everyForModel(requested)) is faster than this kind of report allows; \(everyForModel) is the fastest, so it reads every \(everyForModel). Tell the user."
            lines.append(String(localized: "Every \(every) is the fastest for this; I'll check every \(every)."))
        }
        let calendar = Calendar.autoupdatingCurrent
        if let end = w.expiresAt {
            text += " It stops on its own at \(TimeFormat.full(end, calendar: calendar)), in \(WatchWords.everyForModel(end.timeIntervalSince(now))); tell the user, and that saying \"until I stop it\" keeps it going."
            lines.append(String(localized: "Stops \(TimeFormat.moment(end, now: now, calendar: calendar))", comment: "“Stops 15:30”, “Stops Tomorrow 10:00”"))
        } else {
            text += " It keeps going until the user stops it."
            lines.append(String(localized: "Keeps going until you stop it"))
        }
        if w.config["notify"]?.boolValue == true {
            text += " A notification comes with every reading."
            lines.append(String(localized: "With a notification each time"))
        }
        text += " Its id is \(w.id)."
        let subtitle = look.reading.map { String(localized: "Now \($0.shown.displaySafe.clipped(WatchLimits.readingLimit))") }
        let card = ResultCard(kind: .watcher, title: String(localized: "Showing \(w.title) every \(every)"), subtitle: subtitle,
                              detail: lines.joined(separator: "\n"), refId: w.id, url: w.kind == WatchKind.webValue ? w.config.string("url") : nil)
        let id = w.id
        let undo = UndoAction(label: String(localized: "Stopped showing \(w.title)")) { _ = await engine.remove(id) }
        return ToolResult(text: text, card: card, undo: undo, untrusted: look.reading?.fromOutside == true)
    }

    /// Creates a report, takes its first reading and describes it. A first look that can never work (no such place,
    /// no value where the page was told to look) takes the report away again and says why, so a model can fix its call.
    static func start(_ watcher: Watcher, requested: TimeInterval, engine: WatcherEngine, context: ToolContext) async throws -> ToolResult {
        let added: Watcher
        do { added = try await engine.add(watcher) } catch { throw WatchInput.watchError(error) }
        let look = await engine.firstLook(of: added.id, polite: context.caller != .user)
        if look.final, let problem = look.problem {
            await engine.remove(added.id)
            throw UserFacingError(verbatim: problem)
        }
        return started(await engine.watcher(id: added.id) ?? added, requested: requested, look: look, engine: engine, now: context.now)
    }
}

// MARK: watch.report

struct WatchReportTool: Tool {
    let engine: WatcherEngine
    var parser: @Sendable () -> WhenParser = { WhenParser() }
    /// Where the person is, when they share it: the weather's place when none is named (D48).
    var here: @Sendable () -> KnownPlace? = { nil }

    var spec: ToolSpec {
        ToolSpec(
            name: "watch.report", title: String(localized: "Show a value regularly"),
            description: """
            Tell the user a current value every few seconds or minutes ("every 10 seconds tell me the CPU", "temperature in \
            Fukuoka every minute"). The value updates in place beside the companion; it is not a change alert (that is \
            watch.create). source: metric (this Mac's cpu, memory, battery, disk or network), weather (built in, no address \
            needed: a place's temperature, feels_like, humidity, wind, precipitation or conditions), web (one value on a page \
            or API, found by json_path, selector or regex). Fastest: metrics every 5 s, weather and web every 60 s; a command's \
            output is watch.command with report=true (every 10 s at the fastest). Pass the interval the user asked for: a faster \
            one is raised to the fastest allowed and the result says so; never refuse a request for being too frequent. It stops \
            on its own after 1 hour when it reads more often than once a minute, otherwise after 1 day, unless the user gave an \
            end (until) or said to keep going until they stop it (until_stopped). Tell the user when it stops. Stop it with watch.stop.
            """,
            inputSchema: Schema.object([
                "source": Schema.string("What kind of value.", enum: ["metric", "weather", "web"]),
                "metric": Schema.string("metric: which value of this Mac.", enum: Metric.allCases.map(\.rawValue)),
                "place": Schema.string("weather: the place as the user said it, like \"Fukuoka\" or \"Paris, France\". Leave out for where the user is."),
                "quantity": Schema.string("weather: what to show (default temperature).", enum: WeatherQuantity.allCases.map(\.rawValue)),
                "url": Schema.string("web: the page or API address."),
                "json_path": Schema.string("web: a path into a JSON reply, like current.temperature_2m or data[0].price."),
                "selector": Schema.string("web: a simple CSS selector (tag, .class, #id or tag.class) whose text is the value."),
                "regex": Schema.string("web: a regular expression; its first group (or else the whole match) is the value."),
                "every_seconds": Schema.number("Seconds between readings, as the user asked (60 for every minute)."),
                "until": Schema.string("When to stop, in the user's words (\"6pm\", \"in 2 hours\"). Leave out for the default end."),
                "until_stopped": Schema.boolean("true when the user said to keep going until they stop it."),
                "notify": Schema.boolean("true only when the user asked for a notification each time; otherwise the value just updates in place."),
                "title": Schema.string("Short name (optional), like \"CPU\" or \"Temperature in Fukuoka\"."),
            ], required: ["source"]),
            // Other agents get this Mac's metrics only (ExternalToolPolicy): a web value would let them read pages
            // through Sidefolk (T4).
            risk: .low, capabilities: [.watch, .network], category: .watch, mutates: true, external: true)
    }

    func summary(for input: JSONValue) -> String {
        let every = (try? Report.interval(input)).flatMap { $0 > 0 ? WatchWords.every($0) : nil }
        // The weather with no place named is the person's own (D48).
        let named = input.string("source") == "weather" && input.string("place") == nil
            ? here().map { input.setting("place", .string($0.name)) } ?? input : input
        let what = Self.title(named) ?? String(localized: "a value")
        return every.map { String(localized: "Show \(what) every \($0)") } ?? String(localized: "Show \(what) regularly")
    }

    /// A web value fetches an address the model may have built: Guard weighs it like any other link (T1, T2).
    /// A metric reaches nothing, and the weather only Open-Meteo, whatever the model writes (D47).
    func scope(for input: JSONValue) -> ToolScope {
        switch input.string("source") {
        case "metric": return ToolScope(reach: .nowhere)
        case "weather": return ToolScope(reach: .service(WeatherProbe.service))
        case "web":
            guard let url = input.string("url") else { return .none }
            let text = url.contains("://") ? url : WebTarget.defaultScheme(for: url) + url
            return ToolScope(url: URL(string: text)?.absoluteString ?? text)
        default: return .none
        }
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        var config: JSONValue = .object([:])
        let kind: String
        switch input.string("source") {
        case "metric":
            kind = WatchKind.metric
            config = ["metric": input["metric"] ?? .null]
        case "weather":
            kind = WatchKind.weather
            guard let weather = WeatherProbe.config(place: input.string("place"), here: here(), quantity: input["quantity"] ?? "temperature") else {
                return PlaceNeeded.result
            }
            config = weather
        case "web":
            kind = WatchKind.webValue
            config = ["url": input["url"] ?? .null]
            for key in ["json_path", "selector", "regex"] { config = config.setting(key, input[key]) }
            // Only the user's own typed request reaches this Mac or the local network (SECURITY T11).
            if context.caller == .user, !context.tainted { config = config.setting("allow_local", true) }
        default:
            throw ToolError.invalidInput(String(localized: "“source” must be metric, weather or web."))
        }
        if input["notify"]?.boolValue == true { config = config.setting("notify", true) }
        let end = try Report.end(input, now: context.now, parser: parser())
        if end == nil, input["until_stopped"]?.boolValue == true { config = config.setting("until_stopped", true) }

        let requested = try Report.interval(input)
        let title = input.string("title") ?? Self.title(input.setting("place", config["place"])) ?? String(localized: "Value")
        let watcher = Watcher(kind: kind, title: title, config: config, intervalS: requested, mode: .report, expiresAt: end,
                              source: WatchSource.string(for: context), now: context.now)
        return try await Report.start(watcher, requested: requested, engine: engine, context: context)
    }

    /// "CPU", "Temperature in Fukuoka", "Value on example.com".
    static func title(_ input: JSONValue) -> String? {
        switch input.string("source") {
        case "metric": return input.string("metric").flatMap { Metric(rawValue: $0.lowercased()) }?.title
        case "weather":
            guard let place = WeatherProbe.cleanPlace(input.string("place")) else { return nil }
            return (WeatherQuantity(rawValue: input.string("quantity") ?? "temperature") ?? .temperature).title(place)
        case "web":
            guard let url = try? WebTarget.normalise(input.string("url"), allowLocal: true) else { return nil }
            return String(localized: "Value on \(WebTarget.displayName(url))")
        default: return nil
        }
    }
}
