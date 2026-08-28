import CoreAudio
import Foundation

struct HeadphoneCallActivity: Equatable, Sendable {
    static let inactive = HeadphoneCallActivity(
        headphonesAvailable: false,
        headphoneName: nil,
        anotherProcessIsUsingMicrophone: false,
        headphoneAudioIsRunning: false,
        supportsProcessDetection: false
    )

    let headphonesAvailable: Bool
    let headphoneName: String?
    let anotherProcessIsUsingMicrophone: Bool
    let headphoneAudioIsRunning: Bool
    let supportsProcessDetection: Bool

    var shouldMonitor: Bool {
        guard headphonesAvailable else { return false }
        if supportsProcessDetection {
            return anotherProcessIsUsingMicrophone
        }
        return headphoneAudioIsRunning
    }
}

protocol CallActivityMonitoring: AnyObject {
    var onChange: ((HeadphoneCallActivity) -> Void)? { get set }
    func start()
    func stop()
}

/// Watches Core Audio metadata only. It never opens an audio stream and never
/// receives sample buffers. All work is event-driven except for a short
/// debounce after Core Audio reports that a property changed.
final class HeadphoneCallMonitor: CallActivityMonitoring, @unchecked Sendable {
    var onChange: ((HeadphoneCallActivity) -> Void)?

    private let queue = DispatchQueue(
        label: "app.loudmouth.call-activity",
        qos: .utility
    )
    private let ownProcessID = getpid()
    private var isRunning = false
    private var listeners: [ListenerKey: AudioPropertyListener] = [:]
    private var pendingRefresh: DispatchWorkItem?
    private var lastActivity: HeadphoneCallActivity?

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            self.refreshNow()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.pendingRefresh?.cancel()
            self.pendingRefresh = nil
            for listener in self.listeners.values {
                listener.invalidate()
            }
            self.listeners.removeAll()
            self.lastActivity = nil
        }
    }

    private func scheduleRefresh() {
        guard isRunning, pendingRefresh == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingRefresh = nil
            self.refreshNow()
        }
        pendingRefresh = workItem
        queue.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func refreshNow() {
        guard isRunning else { return }
        let evaluation = evaluateActivity()
        reconcileListeners(with: evaluation.listenerKeys)

        guard evaluation.activity != lastActivity else { return }
        lastActivity = evaluation.activity
        onChange?(evaluation.activity)
    }

    private func evaluateActivity() -> (
        activity: HeadphoneCallActivity,
        listenerKeys: Set<ListenerKey>
    ) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var listenerKeys: Set<ListenerKey> = [
            ListenerKey(
                objectID: system,
                selector: kAudioHardwarePropertyDefaultOutputDevice,
                scope: kAudioObjectPropertyScopeGlobal
            )
        ]

        let defaultOutputID: AudioDeviceID? = readScalar(
            objectID: system,
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )

        let processListKey = ListenerKey(
            objectID: system,
            selector: kAudioHardwarePropertyProcessObjectList,
            scope: kAudioObjectPropertyScopeGlobal
        )
        var activeProcessOutputIDs: [AudioDeviceID] = []
        var anotherProcessIsUsingMicrophone = false
        let processIDs: [AudioObjectID]? = readArray(
            objectID: system,
            selector: kAudioHardwarePropertyProcessObjectList,
            scope: kAudioObjectPropertyScopeGlobal
        )
        let supportsProcessDetection = processIDs != nil

        if supportsProcessDetection {
            listenerKeys.insert(processListKey)
        }

        for processID in processIDs ?? [] {
            let runningInputKey = ListenerKey(
                objectID: processID,
                selector: kAudioProcessPropertyIsRunningInput,
                scope: kAudioObjectPropertyScopeGlobal
            )
            let outputDevicesKey = ListenerKey(
                objectID: processID,
                selector: kAudioProcessPropertyDevices,
                scope: kAudioObjectPropertyScopeOutput
            )
            listenerKeys.insert(runningInputKey)
            listenerKeys.insert(outputDevicesKey)

            let processIDValue: pid_t? = readScalar(
                objectID: processID,
                selector: kAudioProcessPropertyPID,
                scope: kAudioObjectPropertyScopeGlobal
            )
            guard processIDValue != ownProcessID else { continue }

            let isRunningInput: UInt32 = readScalar(
                objectID: processID,
                selector: kAudioProcessPropertyIsRunningInput,
                scope: kAudioObjectPropertyScopeGlobal
            ) ?? 0
            guard isRunningInput != 0 else { continue }

            anotherProcessIsUsingMicrophone = true
            let outputIDs: [AudioDeviceID] = readArray(
                objectID: processID,
                selector: kAudioProcessPropertyDevices,
                scope: kAudioObjectPropertyScopeOutput
            ) ?? []
            activeProcessOutputIDs.append(contentsOf: outputIDs)
        }

        var candidateIDs = activeProcessOutputIDs
        if let defaultOutputID {
            candidateIDs.append(defaultOutputID)
        }

        var seenDeviceIDs: Set<AudioDeviceID> = []
        var headphone: OutputDeviceDescription?
        for deviceID in candidateIDs where seenDeviceIDs.insert(deviceID).inserted {
            listenerKeys.formUnion(deviceListenerKeys(for: deviceID))
            for streamID in streamIDs(for: deviceID, scope: kAudioDevicePropertyScopeOutput) {
                listenerKeys.insert(
                    ListenerKey(
                        objectID: streamID,
                        selector: kAudioStreamPropertyTerminalType,
                        scope: kAudioObjectPropertyScopeGlobal
                    )
                )
            }
            if headphone == nil, let description = describeHeadphone(deviceID) {
                headphone = description
            }
        }

        let activity = HeadphoneCallActivity(
            headphonesAvailable: headphone != nil,
            headphoneName: headphone?.name,
            anotherProcessIsUsingMicrophone: anotherProcessIsUsingMicrophone,
            headphoneAudioIsRunning: headphone?.isRunning ?? false,
            supportsProcessDetection: supportsProcessDetection
        )
        return (activity, listenerKeys)
    }

    private func deviceListenerKeys(for deviceID: AudioDeviceID) -> Set<ListenerKey> {
        [
            ListenerKey(
                objectID: deviceID,
                selector: kAudioObjectPropertyName,
                scope: kAudioObjectPropertyScopeGlobal
            ),
            ListenerKey(
                objectID: deviceID,
                selector: kAudioDevicePropertyTransportType,
                scope: kAudioObjectPropertyScopeGlobal
            ),
            ListenerKey(
                objectID: deviceID,
                selector: kAudioDevicePropertyJackIsConnected,
                scope: kAudioDevicePropertyScopeOutput
            ),
            ListenerKey(
                objectID: deviceID,
                selector: kAudioDevicePropertyJackIsConnected,
                scope: kAudioObjectPropertyScopeGlobal
            ),
            ListenerKey(
                objectID: deviceID,
                selector: kAudioDevicePropertyDataSource,
                scope: kAudioDevicePropertyScopeOutput
            ),
            ListenerKey(
                objectID: deviceID,
                selector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                scope: kAudioObjectPropertyScopeGlobal
            )
        ]
    }

    private func describeHeadphone(_ deviceID: AudioDeviceID) -> OutputDeviceDescription? {
        let outputStreamIDs = streamIDs(
            for: deviceID,
            scope: kAudioDevicePropertyScopeOutput
        )
        guard !outputStreamIDs.isEmpty else { return nil }

        let name = stringProperty(
            objectID: deviceID,
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? "Headphones"
        let lowercasedName = name.lowercased()
        let nameLooksLikeHeadphones = [
            "headphone", "headset", "airpods", "earbuds", "earphones",
            "beats", "buds", "pods"
        ].contains(where: lowercasedName.contains)

        let transport: UInt32? = readScalar(
            objectID: deviceID,
            selector: kAudioDevicePropertyTransportType,
            scope: kAudioObjectPropertyScopeGlobal
        )
        let isPersonalAudioTransport = transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
            || transport == kAudioDeviceTransportTypeUSB
        let transportLooksLikeHeadphones = isPersonalAudioTransport && !streamIDs(
            for: deviceID,
            scope: kAudioDevicePropertyScopeInput
        ).isEmpty

        let terminalLooksLikeHeadphones = outputStreamIDs.contains { streamID in
            let terminalType: UInt32? = readScalar(
                objectID: streamID,
                selector: kAudioStreamPropertyTerminalType,
                scope: kAudioObjectPropertyScopeGlobal
            )
            return terminalType == kAudioStreamTerminalTypeHeadphones
        }

        let jackConnected: UInt32 = readScalar(
            objectID: deviceID,
            selector: kAudioDevicePropertyJackIsConnected,
            scope: kAudioDevicePropertyScopeOutput
        ) ?? readScalar(
            objectID: deviceID,
            selector: kAudioDevicePropertyJackIsConnected,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? 0

        guard nameLooksLikeHeadphones
                || terminalLooksLikeHeadphones
                || transportLooksLikeHeadphones
                || jackConnected != 0 else {
            return nil
        }

        let isRunning: UInt32 = readScalar(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? 0
        return OutputDeviceDescription(name: name, isRunning: isRunning != 0)
    }

    private func streamIDs(
        for deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) -> [AudioStreamID] {
        readArray(
            objectID: deviceID,
            selector: kAudioDevicePropertyStreams,
            scope: scope
        ) ?? []
    }

    private func reconcileListeners(with desiredKeys: Set<ListenerKey>) {
        let obsoleteKeys = listeners.keys.filter { !desiredKeys.contains($0) }
        for key in obsoleteKeys {
            listeners.removeValue(forKey: key)?.invalidate()
        }

        for key in desiredKeys where listeners[key] == nil {
            guard key.propertyExists else { continue }
            listeners[key] = AudioPropertyListener(
                key: key,
                queue: queue
            ) { [weak self] in
                self?.scheduleRefresh()
            }
        }
    }
}

private struct OutputDeviceDescription {
    let name: String
    let isRunning: Bool
}

private struct ListenerKey: Hashable {
    let objectID: AudioObjectID
    let selector: AudioObjectPropertySelector
    let scope: AudioObjectPropertyScope
    let element: AudioObjectPropertyElement

    init(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) {
        self.objectID = objectID
        self.selector = selector
        self.scope = scope
        self.element = element
    }

    var address: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }

    var propertyExists: Bool {
        var address = address
        return AudioObjectHasProperty(objectID, &address)
    }
}

private final class AudioPropertyListener {
    private let key: ListenerKey
    private let queue: DispatchQueue
    private let block: AudioObjectPropertyListenerBlock
    private var isRegistered: Bool

    init?(
        key: ListenerKey,
        queue: DispatchQueue,
        onChange: @escaping () -> Void
    ) {
        self.key = key
        self.queue = queue
        block = { _, _ in onChange() }
        var address = key.address
        isRegistered = AudioObjectAddPropertyListenerBlock(
            key.objectID,
            &address,
            queue,
            block
        ) == noErr
        if !isRegistered { return nil }
    }

    func invalidate() {
        guard isRegistered else { return }
        var address = key.address
        AudioObjectRemovePropertyListenerBlock(
            key.objectID,
            &address,
            queue,
            block
        )
        isRegistered = false
    }

    deinit {
        invalidate()
    }
}

private func readScalar<T: FixedWidthInteger>(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
) -> T? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: element
    )
    guard AudioObjectHasProperty(objectID, &address) else { return nil }
    var value: T = 0
    var byteCount = UInt32(MemoryLayout<T>.size)
    let status = withUnsafeMutablePointer(to: &value) { pointer in
        AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &byteCount,
            pointer
        )
    }
    return status == noErr && byteCount == MemoryLayout<T>.size ? value : nil
}

private func readArray<T: FixedWidthInteger>(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
) -> [T]? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: element
    )
    guard AudioObjectHasProperty(objectID, &address) else { return nil }
    var byteCount: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        objectID,
        &address,
        0,
        nil,
        &byteCount
    ) == noErr else { return nil }
    guard byteCount > 0 else { return [] }

    let count = Int(byteCount) / MemoryLayout<T>.stride
    var values = [T](repeating: 0, count: count)
    let status = values.withUnsafeMutableBytes { bytes in
        AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &byteCount,
            bytes.baseAddress!
        )
    }
    guard status == noErr else { return nil }
    return values
}

private func stringProperty(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: element
    )
    guard AudioObjectHasProperty(objectID, &address) else { return nil }
    var value: CFString?
    var byteCount = UInt32(MemoryLayout<CFString?>.size)
    let status = withUnsafeMutablePointer(to: &value) { pointer in
        AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &byteCount,
            pointer
        )
    }
    return status == noErr ? value as String? : nil
}
