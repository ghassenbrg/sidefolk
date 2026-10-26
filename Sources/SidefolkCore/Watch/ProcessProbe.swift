import Darwin
import Foundation

public struct ProcessEntry: Sendable, Equatable {
    public var pid: Int32
    public var name: String
    /// Seconds since 1970 when the process started; tells a process from a later one that reused its pid.
    public var startedAt: Double

    public init(pid: Int32, name: String, startedAt: Double) {
        self.pid = pid
        self.name = name
        self.startedAt = startedAt
    }
}

/// A view of the running processes. The real one reads libproc; tests can fake it.
public protocol ProcessTable: Sendable {
    /// Running (not zombie) processes with this name, case-insensitive.
    func find(name: String) -> [ProcessEntry]
    func entry(pid: Int32) -> ProcessEntry?
}

/// Reads the process list straight from the kernel through libproc: no `ps`, no child process.
public struct LibprocTable: ProcessTable {
    public init() {}

    public func entry(pid: Int32) -> ProcessEntry? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        guard info.pbi_status != 5 /* SZOMB: exited, waiting to be reaped */ else { return nil }
        let name = withUnsafeBytes(of: &info.pbi_name) { raw -> String in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        let comm = withUnsafeBytes(of: &info.pbi_comm) { raw -> String in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        let started = Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1e6
        return ProcessEntry(pid: pid, name: name.isEmpty ? comm : name, startedAt: started)
    }

    public func find(name: String) -> [ProcessEntry] {
        let wanted = name.lowercased()
        var out: [ProcessEntry] = []
        var nameBuffer = [CChar](repeating: 0, count: 256)
        for pid in allPids() {
            guard proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 else { continue }
            let short = Self.text(nameBuffer).lowercased()
            var hit = short == wanted
            if !hit, wanted.count > 15, short.count >= 15, wanted.hasPrefix(short) {
                // proc_name cuts long names; settle it with the executable's file name.
                var path = [CChar](repeating: 0, count: 1024)
                if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
                    hit = URL(fileURLWithPath: Self.text(path)).lastPathComponent.lowercased() == wanted
                }
            }
            if hit, let e = entry(pid: pid) { out.append(e) }
        }
        return out
    }

    private static func text(_ buffer: [CChar]) -> String {
        buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    private func allPids() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 64)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard got > 0 else { return [] }
        return pids.prefix(Int(got)).filter { $0 > 0 }
    }
}

public struct ProcessExitsProbe: WatcherProbe {
    public let kind = WatchKind.processExits
    public var defaultInterval: TimeInterval { 5 }
    public var minimumInterval: TimeInterval { 3 }

    let table: any ProcessTable

    public init(table: any ProcessTable = LibprocTable()) { self.table = table }

    public func prepare(_ watcher: Watcher) throws -> Watcher {
        var w = watcher
        let name = w.config.string("name")
        let pid = w.config["pid"]?.intValue
        guard name != nil || pid != nil else { throw WatchError.invalid(String(localized: "Tell me which program to watch, by name or by its process number.")) }
        if let pid, pid <= 0 || pid > Int(Int32.max) { throw WatchError.invalid(String(localized: "That isn't a valid process number.")) }
        if let name, name.count > 100 || name.contains("/") { throw WatchError.invalid(String(localized: "Use the program's name, like Xcode, not a path.")) }
        var config: [String: JSONValue] = [:]
        if let name { config["name"] = .string(name) }
        if let pid { config["pid"] = .number(Double(pid)) }
        w.config = .object(config)
        return w
    }

    /// A process number goes in as text: as a number it would get a thousands separator ("Process 4,312").
    static func label(_ config: JSONValue) -> String {
        (config.string("name") ?? config["pid"]?.intValue.map { String(localized: "Process \(String($0))") } ?? String(localized: "That program"))
            .displaySafe.clipped(60)
    }

    public func check(_ w: Watcher, now: Date) async throws -> ProbeResult {
        let previous = w.lastState
        let label = Self.label(w.config)
        let wasSeen = previous?["seen"]?.boolValue ?? false

        var running: [ProcessEntry]
        if let pid = w.config["pid"]?.intValue {
            // A pid is a process only while it keeps its start time and (if given) its name.
            let tracked = previous?["start"]?.doubleValue
            running = table.entry(pid: Int32(pid)).map { [$0] } ?? []
            running = running.filter { entry in
                if let tracked { return abs(entry.startedAt - tracked) < 1 }
                if let name = w.config.string("name") { return entry.name.lowercased() == name.lowercased() }
                return true
            }
        } else {
            running = table.find(name: w.config.string("name") ?? "")
        }

        if !running.isEmpty {
            var state: [String: JSONValue] = ["seen": true, "reported": false, "pids": .array(running.prefix(8).map { .number(Double($0.pid)) })]
            if let first = running.first { state["start"] = .number(first.startedAt) }
            return ProbeResult(state: .object(state))
        }
        if wasSeen {
            return ProbeResult(state: ["seen": false, "reported": true], triggered: true, summary: String(localized: "\(label) exited"))
        }
        // Never seen running. Say so once, in the card that confirms the new watcher ("Xcode isn't running"), and keep
        // waiting for it to start and then quit; no notice on top of the card, and none again and again.
        return ProbeResult(state: ["seen": false, "reported": true],
                           firstLookNote: previous == nil ? String(localized: "\(label) isn't running right now.") : nil)
    }

    public func eventTargets(for watcher: Watcher) -> [WatchEventTarget] {
        (watcher.lastState?["pids"]?.arrayValue ?? []).compactMap { $0.intValue.map { .process(Int32($0)) } }
    }
}
