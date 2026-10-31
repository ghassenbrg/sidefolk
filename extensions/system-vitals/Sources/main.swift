import SidefolkExtensionKit

// System Vitals, an extension that ships with Sidefolk: no internet, no files, one program (pmset).
let ext = Extension(name: "system-vitals")

ext.tool("battery", "Battery status", "Battery charge in percent, whether it is charging, and the time remaining.") { _ in
    Vitals.describe(try Vitals.battery())
}
ext.tool("disk", "Disk space", "Free and total space on the startup disk (and the home disk if it is a different one).") { _ in
    Vitals.describe(Vitals.disks())
}
ext.tool("memory", "Memory use", "How much memory is installed and in use, and the system's memory pressure.") { _ in
    try Vitals.memory()
}
ext.tool("about", "About this Mac", "This Mac's processor, cores, memory, macOS version and how long it has been on.") { _ in
    Vitals.about()
}

// Both watchers tell once when the reading crosses the line, not at every check while it stays there.
ext.watcher("battery_low") { settings, state in
    let b = try Vitals.battery()
    let low = (b.percent ?? 100) < (settings.int("below_percent") ?? 20) && !Vitals.charging(b)
    return Check(triggered: low && state["low"] as? Bool != true, state: ["low": low], summary: Vitals.describe(b))
}
ext.watcher("disk_low") { settings, state in
    guard let startup = Vitals.disks().first else { throw Problem(L("The startup disk didn't report its space.")) }
    let low = startup.free / 1e9 < (settings.double("below_gb") ?? 10)
    let summary = low ? L("Only {free} free on the startup disk.", ["free": Vitals.gb(startup.free)]) : Vitals.describe([startup])
    return Check(triggered: low && state["low"] as? Bool != true, state: ["low": low], summary: summary)
}

await ext.serve()
