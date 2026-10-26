import CoreAudio
import Foundation

/// Core Audio questions voice needs answered, without asking for any permission.
enum AudioDevices {
    /// The Mac's own microphone, when it has one. Listening through it leaves AirPods in their
    /// high-quality mode (opening their microphone switches them to call quality) and keeps a dock or
    /// interface someone plugged in for other work out of it.
    static func builtInInput() -> AudioDeviceID? {
        devices().first { isBuiltIn($0) && hasInput($0) }
    }

    /// Whether another app is recording right now (a call, a voice memo): the same signal behind
    /// the orange dot. The companion stays silent then (D34). Bluetooth headsets may not report it.
    static func inputInUseElsewhere() -> Bool {
        let me = getpid()
        return processes().contains { process in
            pid(of: process) != me && (read(process, kAudioProcessPropertyIsRunningInput, as: UInt32.self) ?? 0) != 0
        }
    }

    // MARK: Plumbing

    private static func devices() -> [AudioDeviceID] {
        list(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
    }

    private static func processes() -> [AudioObjectID] {
        list(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
    }

    private static func pid(of process: AudioObjectID) -> pid_t? {
        read(process, kAudioProcessPropertyPID, as: pid_t.self)
    }

    private static func isBuiltIn(_ device: AudioDeviceID) -> Bool {
        read(device, kAudioDevicePropertyTransportType, as: UInt32.self) == kAudioDeviceTransportTypeBuiltIn
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
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
