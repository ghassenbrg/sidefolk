import Darwin
import Foundation
import IOKit.ps

/// What the Mac says about itself, for metric reports. Every call is a few system calls (no process, no
/// shell), cheap enough for a reading every few seconds. Tests use a fake.
public protocol SystemSampling: Sendable {
    /// Seconds since boot on a clock that never jumps; rates are measured against it.
    func uptime() -> TimeInterval
    /// Processor time since boot, all cores together.
    func cpuTicks() -> CPUTicks?
    func memory() -> (used: UInt64, total: UInt64)?
    /// Nil on a Mac without a battery.
    func battery() -> BatteryState?
    /// The startup disk.
    func disk() -> (free: Int64, total: Int64)?
    /// Bytes through the Mac's network interfaces since they came up.
    func networkBytes() -> (received: UInt64, sent: UInt64)?
}

public struct CPUTicks: Sendable, Equatable {
    public var busy: UInt64
    public var total: UInt64
    public init(busy: UInt64, total: UInt64) {
        self.busy = busy
        self.total = total
    }
}

public struct BatteryState: Sendable, Equatable {
    public var percent: Int
    public var charging: Bool
    public var onPower: Bool
    public init(percent: Int, charging: Bool, onPower: Bool) {
        self.percent = percent
        self.charging = charging
        self.onPower = onPower
    }
}

/// The real Mac: Mach host statistics, IOKit power sources, the volume's resource values and the routing table.
public struct MacSampler: SystemSampling {
    /// One send right, taken once: `mach_host_self()` adds a reference every time it is called.
    private static let host = mach_host_self()

    public init() {}

    public func uptime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    public func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(Self.host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard status == KERN_SUCCESS else { return nil }
        let (user, system, idle, nice) = (UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1), UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3))
        return CPUTicks(busy: user + system + nice, total: user + system + idle + nice)
    }

    /// "Used" as Activity Monitor counts it: app memory, wired and compressed.
    public func memory() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(Self.host, HOST_VM_INFO64, $0, &count) }
        }
        var pageSize: vm_size_t = 0
        guard status == KERN_SUCCESS, host_page_size(Self.host, &pageSize) == KERN_SUCCESS else { return nil }
        let app = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        let pages = app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return (pages * UInt64(pageSize), ProcessInfo.processInfo.physicalMemory)
    }

    public func battery() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return BatteryState(percent: Int((Double(current) / Double(max) * 100).rounded()),
                                charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                                onPower: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }

    /// Free as Finder counts it: room for important things, purgeable space included.
    public func disk() -> (free: Int64, total: Int64)? {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        guard let free = values?.volumeAvailableCapacityForImportantUsage, let total = values?.volumeTotalCapacity else { return nil }
        return (free, Int64(total))
    }

    /// Ethernet and Wi-Fi interfaces ("en…") that are up, from the 64-bit counters (the 32-bit ones in
    /// `getifaddrs` wrap after 4 GB). Tunnels and bridges are left out: they would count the same bytes twice.
    public func networkBytes() -> (received: UInt64, sent: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }
        var received: UInt64 = 0, sent: UInt64 = 0
        var offset = 0
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        buffer.withUnsafeBytes { raw in
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let up = info.ifm_flags & IFF_UP != 0 && info.ifm_flags & IFF_LOOPBACK == 0
                    if up, if_indextoname(UInt32(info.ifm_index), &name) != nil,
                       String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self).hasPrefix("en") {
                        received += info.ifm_data.ifi_ibytes
                        sent += info.ifm_data.ifi_obytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return (received, sent)
    }
}
