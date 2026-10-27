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
        guard let percent = b.percent else { return "This Mac has no battery; it runs on \(b.source ?? "power")." }
        return "Battery at \(percent)%, \(b.state)" + (b.remaining.map { " (\($0) left)" } ?? "") + "."
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
        for (label, path) in [("Startup disk", "/"), ("Home", Paths.home)] {
            var st = statvfs()
            guard statvfs(path, &st) == 0 else { continue }
            let free = Double(st.f_bavail) * Double(st.f_frsize), total = Double(st.f_blocks) * Double(st.f_frsize)
            if !volumes.contains(where: { $0.total == total }) { volumes.append(Volume(label: label, free: free, total: total)) }
        }
        return volumes
    }

    static func describe(_ volumes: [Volume]) -> String {
        volumes.map { String(format: "%@: %.1f GB free of %.1f GB.", $0.label, $0.free / 1e9, $0.total / 1e9) }.joined(separator: " ")
    }

    /// Activity Monitor's "Memory Used": app memory, wired and compressed.
    static func memory() throws -> String {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard status == KERN_SUCCESS, let total: UInt64 = sysctl("hw.memsize") else { throw Problem("The Mac didn't report its memory.") }
        let pageSize: Int = sysctl("hw.pagesize") ?? 16_384
        let page = Double(pageSize)
        let used = (Double(stats.internal_page_count) - Double(stats.purgeable_count) + Double(stats.wire_count)
            + Double(stats.compressor_page_count)) * page
        let level: Int32 = sysctl("kern.memorystatus_vm_pressure_level") ?? 0
        let pressure = [1: "normal", 2: "warning", 4: "critical"][level] ?? "unknown"
        return String(format: "%.1f GB of %.1f GB in use; memory pressure is %@.", used / 1_073_741_824, Double(total) / 1_073_741_824, pressure)
    }

    /// "Apple M3 Pro, 12 cores, 36 GB of memory, macOS 27.0 (25A123); on for 3 days 4 hours."
    static func about() -> String {
        let chip = sysctlString("machdep.cpu.brand_string") ?? "an unknown processor"
        let cores: Int32 = sysctl("hw.physicalcpu") ?? 0
        let memory: UInt64 = sysctl("hw.memsize") ?? 0
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let build = sysctlString("kern.osversion").map { " (\($0))" } ?? ""
        var parts = ["This Mac: \(chip)", "\(cores) cores", "\(memory / 1_073_741_824) GB of memory",
                     "macOS \(version.majorVersion).\(version.minorVersion)\(version.patchVersion > 0 ? ".\(version.patchVersion)" : "")\(build)"]
        if let model = sysctlString("hw.model") { parts.append("model \(model)") }
        return parts.joined(separator: ", ") + "; on for " + uptime() + "."
    }

    static func uptime(now: Date = Date()) -> String {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return "an unknown time" }
        let minutes = Int(now.timeIntervalSince1970) / 60 - boot.tv_sec / 60
        let (days, hours, rest) = (minutes / 1440, minutes % 1440 / 60, minutes % 60)
        func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        if days > 0 { return unit(days, "day") + (hours > 0 ? " " + unit(hours, "hour") : "") }
        return hours > 0 ? unit(hours, "hour") + " " + unit(rest, "minute") : unit(rest, "minute")
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
