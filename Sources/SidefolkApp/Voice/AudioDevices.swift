import CoreAudio
import Darwin
import Foundation
import SidefolkCore

/// Core Audio questions voice needs answered, without asking for any permission.
enum AudioDevices {
    /// Who else has the microphone running right now, by program name: `recording` are apps recording (a call, a
    /// voice memo), which keep the companion silent (D34); `listening` are macOS's own background listeners, which
    /// don't (`VoicePolicy.recordsElsewhere`), named only for the log. Bluetooth headsets may not report either.
    static func microphoneUsers() -> (recording: [String], listening: [String]) {
        let me = getpid()
        var users: (recording: [String], listening: [String]) = ([], [])
        for process in processes() {
            guard let pid = pid(of: process), pid != me, (read(process, kAudioProcessPropertyIsRunningInput, as: UInt32.self) ?? 0) != 0 else { continue }
            let path = executable(of: pid)
            let name = path.map { ($0 as NSString).lastPathComponent } ?? "pid \(pid)"
            if VoicePolicy.recordsElsewhere(executable: path) { users.recording.append(name) } else { users.listening.append(name) }
        }
        return users
    }

    private static func executable(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// The input macOS uses unless an app picks another (System Settings › Sound).
    static func defaultInput() -> AudioDeviceID? {
        read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice, as: AudioDeviceID.self)
    }

    /// The output spoken replies play through (System Settings › Sound).
    static func defaultOutput() -> AudioDeviceID? {
        read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, as: AudioDeviceID.self)
    }

    /// "MacBook Pro Microphone": what the person sees in System Settings › Sound.
    static func name(of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0) }
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    // MARK: Plumbing

    private static func processes() -> [AudioObjectID] {
        list(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
    }

    private static func pid(of process: AudioObjectID) -> pid_t? {
        read(process, kAudioProcessPropertyPID, as: pid_t.self)
    }

    private static func list(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as: T.Type) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }
}
