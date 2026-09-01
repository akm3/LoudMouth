import AudioToolbox
import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isBuiltIn: Bool
}

enum AudioInputDevices {
    static func all() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &byteCount
        ) == noErr else { return [] }

        let count = Int(byteCount) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &byteCount,
            &ids
        ) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasInputStreams(id),
                  let name = stringProperty(id, selector: kAudioObjectPropertyName),
                  let uid = stringProperty(id, selector: kAudioDevicePropertyDeviceUID)
            else { return nil }

            let transport = uint32Property(id, selector: kAudioDevicePropertyTransportType)
            return AudioInputDevice(
                id: id,
                uid: uid,
                name: name,
                isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn
            )
        }
        .sorted {
            if $0.isBuiltIn != $1.isBuiltIn { return $0.isBuiltIn }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static var defaultInputID: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var byteCount = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &byteCount,
            &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    static func preferred(uid: String?) -> AudioInputDevice? {
        let devices = all()
        if let uid, let selected = devices.first(where: { $0.uid == uid }) {
            return selected
        }
        if let builtIn = devices.first(where: \.isBuiltIn) {
            return builtIn
        }
        if let defaultInputID,
           let current = devices.first(where: { $0.id == defaultInputID }) {
            return current
        }
        return devices.first
    }

    private static func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &byteCount)
        return status == noErr && byteCount >= MemoryLayout<AudioStreamID>.size
    }

    private static func stringProperty(
        _ id: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var byteCount = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &byteCount, pointer)
        }
        return status == noErr ? value as String? : nil
    }

    private static func uint32Property(
        _ id: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var byteCount = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &byteCount, &value)
        return status == noErr ? value : nil
    }
}
