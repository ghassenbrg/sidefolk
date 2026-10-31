import Foundation

/// A temporary, device-wide mute. The owner must keep the lease in a process that can restore it
/// even when the extension exits. The backend is injected so recovery can be tested without changing
/// the user's real audio device.
protocol OutputMuteDevice {
    func defaultOutput() throws -> UInt32
    func isMuted(_ device: UInt32) throws -> Bool
    func setMuted(_ muted: Bool, device: UInt32) throws
}

struct OutputMuteLease<Backend: OutputMuteDevice> {
    private let backend: Backend
    private var device: UInt32?
    private var originallyMuted = false

    init(backend: Backend) { self.backend = backend }

    /// Move the lease when the system's default output changes. Restore the old device first so
    /// failed switching never leaves the previous output muted.
    mutating func followDefault() throws {
        let next = try backend.defaultOutput()
        guard next != device else { return }
        try restore()
        let wasMuted = try backend.isMuted(next)
        if !wasMuted { try backend.setMuted(true, device: next) }
        device = next
        originallyMuted = wasMuted
    }

    /// Restore only a mute we introduced and only if it is still on. A person who has unmuted the
    /// output since then has taken control of it and their choice is retained.
    mutating func restore() throws {
        guard let previous = device else { return }
        if !originallyMuted, try backend.isMuted(previous) {
            try backend.setMuted(false, device: previous)
        }
        device = nil
        originallyMuted = false
    }
}
