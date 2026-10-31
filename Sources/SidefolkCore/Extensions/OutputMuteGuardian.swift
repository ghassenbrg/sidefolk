import CoreAudio
import Darwin
import Foundation

/// The helper is started by Sidefolk, not by the sandboxed extension. Its stdin belongs to Sidefolk;
/// EOF means the host stopped or crashed, so the temporary mute can be restored independently of
/// the extension's process tree. It never changes output volume.
public enum OutputMuteGuardian {
    public static func run() -> Int32 {
        let guardian = Guardian()
        guard guardian.start() else { reply("error"); return guardian.safeStartFailure ? 2 : 1 }
        reply("ok")
        _ = FileHandle.standardInput.readDataToEndOfFile()
        return guardian.stop() ? 0 : 1
    }

    private static func reply(_ text: String) {
        try? FileHandle.standardOutput.write(contentsOf: Data((text + "\n").utf8))
    }

    private final class Guardian: @unchecked Sendable {
        private let lock = NSLock()
        private var lease = OutputMuteLease(backend: CoreAudioOutput())
        private var listener: AudioObjectPropertyListenerBlock?
        private var timer: DispatchSourceTimer?
        private var failed = false
        private(set) var safeStartFailure = true

        func start() -> Bool {
            var address = Self.defaultAddress
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.changed() }
            lock.lock()
            guard AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.global(), block) == noErr else {
                lock.unlock()
                return false
            }
            listener = block
            do { try lease.followDefault() } catch {
                failed = true
                do { try lease.restore() } catch { safeStartFailure = false }
                listener = nil
                lock.unlock()
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.global(), block)
                return false
            }
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in self?.verify() }
            self.timer = timer
            timer.resume()
            lock.unlock()
            return true
        }

        /// A person can unmute the Mac in Control Center while sharing. Respect that choice and
        /// tell the extension rather than silently claiming that sound is still TV-only.
        private func verify() {
            lock.lock(); defer { lock.unlock() }
            guard !failed else { return }
            do {
                try lease.followDefault()
                let output = CoreAudioOutput()
                guard try output.isMuted(output.defaultOutput()) else {
                    failed = true
                    try? lease.restore()
                    OutputMuteGuardian.reply("error")
                    return
                }
            } catch {
                failed = true
                try? lease.restore()
                OutputMuteGuardian.reply("error")
            }
        }

        private func changed() {
            lock.lock(); defer { lock.unlock() }
            guard !failed else { return }
            do { try lease.followDefault() }
            catch {
                failed = true
                try? lease.restore()
                OutputMuteGuardian.reply("error")
            }
        }

        func stop() -> Bool {
            lock.lock()
            failed = true
            let block = listener
            listener = nil
            let timer = timer
            self.timer = nil
            lock.unlock()
            timer?.cancel()
            if let block {
                var address = Self.defaultAddress
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.global(), block)
            }
            lock.lock(); defer { lock.unlock() }
            do { try lease.restore(); return true } catch { return false }
        }

        private static var defaultAddress: AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                       mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        }
    }
}

private struct CoreAudioOutput: OutputMuteDevice {
    private struct AudioFailure: Error {}
    func defaultOutput() throws -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { throw AudioFailure() }
        return device
    }

    func isMuted(_ device: UInt32) throws -> Bool {
        var address = muteAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { throw AudioFailure() }
        return value != 0
    }

    func setMuted(_ muted: Bool, device: UInt32) throws {
        var address = muteAddress
        var writable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &writable) == noErr, writable.boolValue else { throw AudioFailure() }
        var value: UInt32 = muted ? 1 : 0
        guard AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr else { throw AudioFailure() }
    }

    private var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
