import Darwin
import Foundation
import SidefolkExtensionKit

/// Battery, disk and memory as the Mac reports them. Memory and disk come from the system itself; the battery
/// from `pmset`, the one program the manifest lists (it asks powerd, which the sandbox opens for it).
enum Vitals {
    struct Battery {
        var source: String?
        var percent: Int?
        var state = ""
        var remaining: String?
    }

    static func battery() throws -> Battery {
        battery(from: try run("/usr/bin/pmset", ["-g", "batt"], timeout: 10).out)
    }

    /// `pmset -g batt`: "Now drawing from 'Battery Power'" then "-InternalBattery-0 (id=…)	84%; discharging; 5:12 remaining …".
    static func battery(from out: String) -> Battery {
        var reading = Battery(source: out.firstMatch(of: /Now drawing from '([^']+)'/).map { String($0.1) })
        if let m = out.firstMatch(of: /(\d+)%;\s*([^;]+);/) {
            reading.percent = Int(m.1)
            reading.state = m.2.trimmingCharacters(in: .whitespaces)
            reading.remaining = out.firstMatch(of: /(\d+:\d+) remaining/).map { String($0.1) }.flatMap { $0 == "0:00" ? nil : $0 }
        }
        return reading
    }

    static func describe(_ b: Battery) -> String {
        guard let percent = b.percent else { return L("This Mac has no battery; it runs on {source}.", ["source": b.source ?? L("power")]) }
        let values = ["percent": Format.percent(points: Double(percent)), "state": state(b.state)]
        if let left = b.remaining { return L("Battery at {percent}, {state} ({time} left).", values.merging(["time": left]) { a, _ in a }) }
        return L("Battery at {percent}, {state}.", values)
    }

    /// pmset's words for the battery, in the person's language; one it hasn't said before as it says it.
    static func state(_ raw: String) -> String {
        switch raw {
        case "charging": L("charging")
        case "charged": L("charged")
        case "discharging": L("discharging")
        case "finishing charge": L("finishing charge")
        case "AC attached": L("plugged in, not charging")
        default: raw
        }
    }

    static func charging(_ b: Battery) -> Bool {
        ["charging", "charged", "finishing charge", "AC attached"].contains(b.state)
    }

    struct Volume {
        var label: String
        var free: Double
        var total: Double
    }

    /// The startup disk, and the home disk when it is another one (same APFS container: counted once).
    static func disks() -> [Volume] {
        var volumes: [Volume] = []
        for (label, path) in [(L("Startup disk"), "/"), (L("Home"), Paths.home)] {
            var st = statvfs()
            guard statvfs(path, &st) == 0 else { continue }
            let free = Double(st.f_bavail) * Double(st.f_frsize), total = Double(st.f_blocks) * Double(st.f_frsize)
            if !volumes.contains(where: { $0.total == total }) { volumes.append(Volume(label: label, free: free, total: total)) }
        }
        return volumes
    }

    static func describe(_ volumes: [Volume]) -> String {
        volumes.map { L("{disk}: {free} free of {total}.", ["disk": $0.label, "free": gb($0.free), "total": gb($0.total)]) }.joined(separator: " ")
    }

    /// "12.3 GB" in the person's digits (gigabytes as the Finder counts them).
    static func gb(_ bytes: Double, per: Double = 1e9) -> String {
        (bytes / per).formatted(.number.precision(.fractionLength(1)).locale(Language.locale)) + " GB"
    }

    /// Activity Monitor's "Memory Used": app memory, wired and compressed.
    static func memory() throws -> String {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard status == KERN_SUCCESS, let total: UInt64 = sysctl("hw.memsize") else { throw Problem(L("The Mac didn't report its memory.")) }
        let pageSize: Int = sysctl("hw.pagesize") ?? 16_384
        let page = Double(pageSize)
        let used = (Double(stats.internal_page_count) - Double(stats.purgeable_count) + Double(stats.wire_count)
            + Double(stats.compressor_page_count)) * page
        let level: Int32 = sysctl("kern.memorystatus_vm_pressure_level") ?? 0
        let pressure = [1: L("normal"), 2: L("warning"), 4: L("critical")][level] ?? L("unknown")
        return L("{used} of {total} in use; memory pressure is {pressure}.",
                 ["used": gb(used, per: 1_073_741_824), "total": gb(Double(total), per: 1_073_741_824), "pressure": pressure])
    }

    /// "Apple M3 Pro, 12 cores, 36 GB of memory, macOS 27.0 (25A123); on for 3 days 4 hours."
    static func about() -> String {
        let chip = sysctlString("machdep.cpu.brand_string") ?? L("an unknown processor")
        let cores: Int32 = sysctl("hw.physicalcpu") ?? 0
        let memory: UInt64 = sysctl("hw.memsize") ?? 0
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let build = sysctlString("kern.osversion").map { " (\($0))" } ?? ""
        var parts = [L("This Mac: {chip}", ["chip": chip]), L(one: "{count} core", other: "{count} cores", count: Int(cores)),
                     L("{memory} of memory", ["memory": "\(memory / 1_073_741_824) GB"]),
                     "macOS \(version.majorVersion).\(version.minorVersion)\(version.patchVersion > 0 ? ".\(version.patchVersion)" : "")\(build)"]
        if let model = sysctlString("hw.model") { parts.append(L("model {model}", ["model": model])) }
        return L("{about}; on for {time}.", ["about": parts.joined(separator: L(", ")), "time": uptime()])
    }

    static func uptime(now: Date = Date()) -> String {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return L("an unknown time") }
        let minutes = Int(now.timeIntervalSince1970) / 60 - boot.tv_sec / 60
        return Format.duration(Double(minutes) * 60, units: minutes >= 1440 ? [.days, .hours] : [.hours, .minutes], width: .wide)
    }

    static func sysctl<T>(_ name: String) -> T? {
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        var size = MemoryLayout<T>.size
        return sysctlbyname(name, value, &size, nil, 0) == 0 ? value.pointee : nil
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }
}
