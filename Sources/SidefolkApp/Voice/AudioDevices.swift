import CoreAudio
import Foundation

/// Core Audio questions voice needs answered, without asking for any permission.
enum AudioDevices {
    /// Whether another app is recording right now (a call, a voice memo): the same signal behind
    /// the orange dot. The companion stays silent then (D34). Bluetooth headsets may not report it.
    static func inputInUseElsewhere() -> Bool {
        let me = getpid()
        return processes().contains { process in
            pid(of: process) != me && (read(process, kAudioProcessPropertyIsRunningInput, as: UInt32.self) ?? 0) != 0
        }
    }

    /// The input macOS uses unless an app picks another (System Settings › Sound).
    static func defaultInput() -> AudioDeviceID? {
        read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice, as: AudioDeviceID.self)
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
