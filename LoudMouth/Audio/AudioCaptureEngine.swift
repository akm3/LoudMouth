import AVFoundation
import AudioToolbox
import CoreMedia

final class AudioCaptureEngine: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case noInput
        case unsupportedInputFormat

        var errorDescription: String? {
            switch self {
            case .noInput:
                return "No microphone input is available."
            case .unsupportedInputFormat:
                return "The microphone reported an unsupported audio format."
            }
        }
    }

    var onFrame: (@Sendable (LevelFrame) -> Void)?

    private let session = AVCaptureSession()
    private let sampleQueue = DispatchQueue(
        label: "app.loudmouth.capture-samples",
        qos: .utility
    )
    private var captureInput: AVCaptureDeviceInput?
    private var captureOutput: AVCaptureAudioDataOutput?
    private var pendingDuration: TimeInterval = 0
    private var pendingPeakDecibelsFS: Float = -80
    private var pendingVoiceDetected = false

    private static let frameDeliveryInterval: TimeInterval = 0.10

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    static var permissionStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    @discardableResult
    func start(preferredMicrophoneUID: String?) throws -> AudioInputDevice {
        stop()

        let coreAudioDevice = AudioInputDevices.preferred(uid: preferredMicrophoneUID)
        guard let captureDevice = captureDevice(matching: coreAudioDevice) else {
            throw CaptureError.noInput
        }

        let input = try AVCaptureDeviceInput(device: captureDevice)
        let output = AVCaptureAudioDataOutput()

        // Request a simple PCM representation for level measurement. These
        // buffers remain in memory and are released immediately after use.
        output.audioSettings = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        output.setSampleBufferDelegate(self, queue: sampleQueue)

        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            output.setSampleBufferDelegate(nil, queue: nil)
            throw CaptureError.noInput
        }
        session.addInput(input)

        guard session.canAddOutput(output) else {
            session.removeInput(input)
            session.commitConfiguration()
            output.setSampleBufferDelegate(nil, queue: nil)
            throw CaptureError.unsupportedInputFormat
        }
        session.addOutput(output)
        session.commitConfiguration()

        captureInput = input
        captureOutput = output
        session.startRunning()

        guard session.isRunning else {
            stop()
            throw CaptureError.noInput
        }

        return reportedDevice(for: captureDevice, preferred: coreAudioDevice)
    }

    func stop() {
        captureOutput?.setSampleBufferDelegate(nil, queue: nil)

        if session.isRunning {
            session.stopRunning()
        }

        if captureInput != nil || captureOutput != nil {
            session.beginConfiguration()
            if let captureInput {
                session.removeInput(captureInput)
            }
            if let captureOutput {
                session.removeOutput(captureOutput)
            }
            session.commitConfiguration()
        }

        captureInput = nil
        captureOutput = nil
        sampleQueue.sync {
            pendingDuration = 0
            pendingPeakDecibelsFS = -80
            pendingVoiceDetected = false
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        consume(sampleBuffer: sampleBuffer)
    }

    private func captureDevice(matching preferred: AudioInputDevice?) -> AVCaptureDevice? {
        let devices: [AVCaptureDevice]
        if #available(macOS 14.0, *) {
            devices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            ).devices
        } else {
            devices = AVCaptureDevice.devices(for: .audio)
        }

        if let preferred {
            if let exactMatch = devices.first(where: { $0.uniqueID == preferred.uid }) {
                return exactMatch
            }
            if let nameMatch = devices.first(where: {
                $0.localizedName.compare(
                    preferred.name,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
            }) {
                return nameMatch
            }
        }

        return AVCaptureDevice.default(for: .audio) ?? devices.first
    }

    private func reportedDevice(
        for captureDevice: AVCaptureDevice,
        preferred: AudioInputDevice?
    ) -> AudioInputDevice {
        if let preferred,
           captureDevice.uniqueID == preferred.uid
            || captureDevice.localizedName.compare(
                preferred.name,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame {
            return preferred
        }

        if let matched = AudioInputDevices.all().first(where: {
            $0.uid == captureDevice.uniqueID
                || $0.name.compare(
                    captureDevice.localizedName,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
        }) {
            return matched
        }

        return AudioInputDevice(
            id: AudioDeviceID(kAudioObjectUnknown),
            uid: captureDevice.uniqueID,
            name: captureDevice.localizedName,
            isBuiltIn: false
        )
    }

    private func consume(sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        else { return }

        guard let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
            formatDescription
        )?.pointee,
              streamDescription.mFormatID == kAudioFormatLinearPCM,
              streamDescription.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              streamDescription.mBitsPerChannel == 32,
              streamDescription.mSampleRate > 0
        else { return }

        // The requested output is interleaved PCM, so one stack-allocated
        // AudioBuffer is sufficient. Avoiding a size query and heap allocation
        // for every hardware callback materially lowers idle CPU usage.
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 0,
                mDataByteSize: 0,
                mData: nil
            )
        )
        var retainedBlockBuffer: CMBlockBuffer?
        let dataStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &bufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &retainedBlockBuffer
        )
        guard dataStatus == noErr else { return }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }
        let features = withUnsafePointer(to: &bufferList) { audioFeatures(in: $0) }
        let duration = Double(frameCount) / streamDescription.mSampleRate
        pendingDuration += duration
        pendingPeakDecibelsFS = max(pendingPeakDecibelsFS, features.decibelsFS)
        pendingVoiceDetected = pendingVoiceDetected || features.voiceDetected

        // Capture devices may deliver close to one hundred buffers per second.
        // Level and UI logic do not need that cadence, so combine them into a
        // stable 10 Hz stream to avoid needless main-thread redraws.
        guard pendingDuration >= Self.frameDeliveryInterval else { return }

        onFrame?(LevelFrame(
            decibelsFS: pendingPeakDecibelsFS,
            duration: pendingDuration,
            speechConfidence: pendingVoiceDetected ? 1 : 0,
            hasSpeechClassification: true
        ))
        pendingDuration = 0
        pendingPeakDecibelsFS = -80
        pendingVoiceDetected = false
    }

    private func audioFeatures(
        in bufferList: UnsafePointer<AudioBufferList>
    ) -> (decibelsFS: Float, voiceDetected: Bool) {
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferList)
        )
        var loudest: Float = -80
        var voiceDetected = false

        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            var sumOfSquares: Float = 0
            var crossings = 0
            var previousWasPositive = samples[0] >= 0
            for index in 0..<count {
                let sample = samples[index]
                sumOfSquares += sample * sample
                if index > 0 {
                    let isPositive = sample >= 0
                    if isPositive != previousWasPositive {
                        crossings += 1
                    }
                    previousWasPositive = isPositive
                }
            }
            let rms = sqrt(sumOfSquares / Float(count))
            let level = max(-80, 20 * log10(max(rms, 0.000_000_1)))
            loudest = max(loudest, level)

            // A zero-crossing voice gate is dramatically cheaper than running
            // a general-purpose ML classifier continuously. The broad human
            // speech range plus AppModel's hold time keeps it responsive to
            // normal, quiet, and emphatic speech while rejecting steady noise.
            if level > -78 {
                let crossingRate = Double(crossings) / Double(max(count - 1, 1))
                voiceDetected = voiceDetected || (0.002...0.28).contains(crossingRate)
            }
        }
        return (loudest, voiceDetected)
    }
}
