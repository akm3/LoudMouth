import AppKit
import AVFoundation
import Combine
import Foundation

enum MenuMouthState: Equatable {
    case idle
    case quiet
    case elevated
    case loud
}

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case needsPermission
        case permissionDenied
        case readyToCalibrate
        case calibrating
        case listening
        case waitingForCall
        case paused
        case error(String)
    }

    @Published private(set) var phase: Phase
    @Published private(set) var relativeDecibels: Float = 0
    @Published private(set) var meterProgress: Double = 0.28
    @Published private(set) var isLoud = false
    @Published private(set) var voiceDetected = false
    @Published private(set) var soundDetected = false
    @Published private(set) var mouthActivity: Double = 0
    @Published private(set) var calibrationProgress: Double = 0
    @Published private(set) var calibrationFrameCount = 0
    @Published private(set) var calibrationSignalFrameCount = 0
    @Published private(set) var currentInputDecibelsFS: Float = -80
    @Published private(set) var isPreparingInput = false
    @Published private(set) var inputDeviceName = "Built-in microphone"
    @Published private(set) var callActivity = HeadphoneCallActivity.inactive

    let settings: AppSettings

    private let captureEngine = AudioCaptureEngine()
    private let callActivityMonitor: CallActivityMonitoring?
    private let overlayController = LoudAlertController()
    private var processor: LoudnessProcessor
    private var calibration = CalibrationAccumulator()
    private var calibrationTimeline = CalibrationTimeline()
    private var calibrationTimer: Timer?
    private let captureControlQueue = DispatchQueue(
        label: "app.loudmouth.capture-control",
        qos: .userInitiated
    )
    private var captureOperationID = 0
    private var speechHold: TimeInterval = 0
    private var automaticSleepWorkItem: DispatchWorkItem?
    private var manualMonitoringOverride = false
    private var cancellables: Set<AnyCancellable> = []

    init(
        settings: AppSettings = AppSettings(),
        callActivityMonitor: CallActivityMonitoring? = HeadphoneCallMonitor()
    ) {
        self.settings = settings
        self.callActivityMonitor = callActivityMonitor
        let baseline = settings.baselineDecibelsFS ?? -28
        processor = LoudnessProcessor(
            baselineDecibelsFS: baseline,
            thresholdDecibels: Float(settings.thresholdDecibels),
            alertDelay: settings.alertDelay
        )

        switch AudioCaptureEngine.permissionStatus {
        case .authorized:
            if settings.baselineDecibelsFS == nil {
                phase = .readyToCalibrate
            } else {
                phase = settings.monitorOnlyDuringHeadphoneCalls
                    ? .waitingForCall
                    : .paused
            }
        case .denied, .restricted:
            phase = .permissionDenied
        default:
            phase = .needsPermission
        }

        captureEngine.onFrame = { [weak self] frame in
            DispatchQueue.main.async {
                self?.consume(frame)
            }
        }

        callActivityMonitor?.onChange = { [weak self] activity in
            DispatchQueue.main.async {
                self?.handleCallActivity(activity)
            }
        }

        Publishers.CombineLatest3(
            settings.$thresholdDecibels,
            settings.$alertDelay,
            settings.$showOverlay
        )
            .sink { [weak self] threshold, delay, showOverlay in
                Task { @MainActor in
                    self?.applySettings(
                        thresholdDecibels: threshold,
                        alertDelay: delay,
                        showOverlay: showOverlay
                    )
                }
            }
            .store(in: &cancellables)

        settings.$monitorOnlyDuringHeadphoneCalls
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                Task { @MainActor in
                    self?.automaticMonitoringSettingChanged(enabled: enabled)
                }
            }
            .store(in: &cancellables)

        if AudioCaptureEngine.permissionStatus == .authorized,
           settings.baselineDecibelsFS != nil {
            Task { [weak self] in self?.resumeConfiguredMonitoring() }
        }
    }

    static func designPreview(
        isLoud: Bool = false,
        relativeDecibels: Float? = nil,
        mouthActivity: Double? = nil,
        phase previewPhase: Phase = .listening
    ) -> AppModel {
        let defaults = UserDefaults(suiteName: "app.loudmouth.design-preview.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let model = AppModel(settings: settings, callActivityMonitor: nil)
        settings.baselineDecibelsFS = -28
        model.phase = previewPhase
        model.inputDeviceName = "MacBook Pro Microphone"
        if previewPhase == .waitingForCall {
            model.resetLiveIndicators()
        } else {
            model.relativeDecibels = relativeDecibels ?? (isLoud ? 11 : 2)
            model.meterProgress = isLoud ? 0.91 : 0.43
            model.voiceDetected = true
            model.soundDetected = true
            model.mouthActivity = mouthActivity ?? (isLoud ? 0.96 : 0.48)
            model.isLoud = isLoud
        }
        return model
    }

    var menuMouthState: MenuMouthState {
        guard phase == .listening || phase == .calibrating,
              soundDetected else { return .idle }
        if isLoud { return .loud }
        if isElevated { return .elevated }
        return .quiet
    }

    var isElevated: Bool {
        soundDetected && relativeDecibels >= warningThresholdDecibels
    }

    var statusTitle: String {
        if isLoud { return "You’re getting loud" }
        if !voiceDetected { return "Listening" }
        if isElevated {
            return "A little elevated"
        }
        return "Sounds comfortable"
    }

    var statusDetail: String {
        if isLoud { return "Ease back toward your natural voice." }
        if !voiceDetected { return "Speak normally — I’ll keep an ear out." }
        return "Your voice is close to its calibrated level."
    }

    var waitingTitle: String {
        callActivity.headphonesAvailable
            ? "Waiting for your call"
            : "Sleeping to save energy"
    }

    var waitingDetail: String {
        if callActivity.headphonesAvailable {
            let name = callActivity.headphoneName ?? "Headphones"
            return "\(name) detected. Monitoring starts when a call uses the microphone."
        }
        return "Connect headphones and start a call — LoudMouth will wake automatically."
    }

    var automaticMonitoringStatus: String {
        guard settings.monitorOnlyDuringHeadphoneCalls else {
            return phase == .paused ? "Paused" : "Always monitoring"
        }
        switch phase {
        case .listening:
            return manualMonitoringOverride ? "Manually monitoring" : "Headphone call detected"
        case .waitingForCall:
            return callActivity.headphonesAvailable
                ? "Headphones detected · Waiting for call"
                : "Sleeping · Waiting for headphones"
        case .paused:
            return "Paused"
        case .calibrating:
            return "Calibration in progress"
        default:
            return "Automatic"
        }
    }

    var calibrationInputStatus: String {
        if isPreparingInput {
            return "Connecting to the microphone…"
        }
        guard calibrationFrameCount > 0 else {
            return "Waiting for microphone data…"
        }
        if currentInputDecibelsFS >= -1 {
            return "Input is clipping — move back a little"
        }
        if calibrationSignalFrameCount == 0 {
            return "No microphone signal detected yet"
        }
        if currentInputDecibelsFS < -62 {
            return "Quiet signal detected — keep talking"
        }
        return "Microphone signal detected"
    }

    var calibrationInputLevel: String {
        guard calibrationFrameCount > 0 else { return "" }
        return String(format: "Live input %.0f dBFS", currentInputDecibelsFS)
    }

    func requestMicrophoneAccess() {
        Task {
            let granted = await AudioCaptureEngine.requestPermission()
            guard granted else {
                phase = .permissionDenied
                return
            }
            if settings.baselineDecibelsFS == nil {
                phase = .readyToCalibrate
            } else {
                resumeConfiguredMonitoring()
            }
        }
    }

    func beginCalibration() {
        cancelAutomaticSleep()
        callActivityMonitor?.stop()
        manualMonitoringOverride = false
        stopCalibrationTimer()
        calibration.reset()
        calibrationProgress = 0
        calibrationFrameCount = 0
        calibrationSignalFrameCount = 0
        currentInputDecibelsFS = -80
        isLoud = false
        overlayController.hide()
        startEngine(calibrating: true)
    }

    func cancelCalibration() {
        stopCalibrationTimer()
        calibration.reset()
        calibrationProgress = 0
        if settings.baselineDecibelsFS == nil {
            stopCaptureEngine()
            phase = .readyToCalibrate
        } else {
            processor.reset(baselineDecibelsFS: settings.baselineDecibelsFS)
            stopCaptureEngine()
            resumeConfiguredMonitoring()
        }
    }

    func startListening() {
        cancelAutomaticSleep()
        callActivityMonitor?.stop()
        manualMonitoringOverride = true
        stopCalibrationTimer()
        guard settings.baselineDecibelsFS != nil else {
            phase = .readyToCalibrate
            return
        }
        startEngine(calibrating: false)
    }

    func pause() {
        cancelAutomaticSleep()
        callActivityMonitor?.stop()
        manualMonitoringOverride = false
        stopCalibrationTimer()
        stopCaptureEngine()
        phase = .paused
        resetLiveIndicators()
    }

    func toggleMonitoring() {
        if phase == .paused || phase == .waitingForCall {
            startListening()
        } else {
            pause()
        }
    }

    func refreshInputDevice() {
        if phase == .listening {
            if settings.monitorOnlyDuringHeadphoneCalls && !manualMonitoringOverride {
                startEngine(calibrating: false)
            } else {
                startListening()
            }
        }
    }

    func resetCalibration() {
        pause()
        settings.baselineDecibelsFS = nil
        phase = .readyToCalibrate
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startEngine(calibrating: Bool) {
        cancelAutomaticSleep()
        captureOperationID &+= 1
        let operationID = captureOperationID
        let preferBuiltInMicrophone = settings.preferBuiltInMicrophone
        let engine = captureEngine

        processor.reset(baselineDecibelsFS: settings.baselineDecibelsFS)
        soundDetected = false
        mouthActivity = 0
        isPreparingInput = true
        phase = calibrating ? .calibrating : .listening

        captureControlQueue.async { [weak self] in
            let result = Result {
                try engine.start(preferBuiltInMicrophone: preferBuiltInMicrophone)
            }
            DispatchQueue.main.async {
                guard let self, self.captureOperationID == operationID else { return }
                self.isPreparingInput = false

                switch result {
                case .success(let device):
                    self.inputDeviceName = device.name
                    if calibrating, self.phase == .calibrating {
                        self.startCalibrationTimer()
                    }
                case .failure(let error):
                    self.phase = .error(error.localizedDescription)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self,
                  self.captureOperationID == operationID,
                  self.isPreparingInput else { return }
            self.isPreparingInput = false
            self.phase = .error(
                "The microphone took too long to start. Check that no other audio app is changing the input device, then try again."
            )
            self.stopCaptureEngine()
        }
    }

    private func stopCaptureEngine() {
        captureOperationID &+= 1
        isPreparingInput = false
        let engine = captureEngine
        captureControlQueue.async {
            engine.stop()
        }
    }

    private func resumeConfiguredMonitoring() {
        cancelAutomaticSleep()
        manualMonitoringOverride = false
        guard settings.baselineDecibelsFS != nil else {
            phase = .readyToCalibrate
            return
        }

        if settings.monitorOnlyDuringHeadphoneCalls,
           let callActivityMonitor {
            phase = .waitingForCall
            resetLiveIndicators()
            callActivityMonitor.start()
        } else {
            callActivityMonitor?.stop()
            startEngine(calibrating: false)
        }
    }

    private func automaticMonitoringSettingChanged(enabled: Bool) {
        guard AudioCaptureEngine.permissionStatus == .authorized,
              settings.baselineDecibelsFS != nil,
              phase != .calibrating,
              phase != .readyToCalibrate else { return }

        cancelAutomaticSleep()
        manualMonitoringOverride = false

        if enabled {
            stopCaptureEngine()
            resumeConfiguredMonitoring()
        } else {
            callActivityMonitor?.stop()
            if phase == .waitingForCall {
                startEngine(calibrating: false)
            }
        }
    }

    private func handleCallActivity(_ activity: HeadphoneCallActivity) {
        callActivity = activity
        guard settings.monitorOnlyDuringHeadphoneCalls,
              settings.baselineDecibelsFS != nil,
              !manualMonitoringOverride else { return }

        if activity.shouldMonitor {
            cancelAutomaticSleep()
            if phase == .waitingForCall {
                startEngine(calibrating: false)
            }
        } else if phase == .listening {
            scheduleAutomaticSleep()
        }
    }

    private func scheduleAutomaticSleep() {
        guard automaticSleepWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.automaticSleepWorkItem = nil
            guard self.settings.monitorOnlyDuringHeadphoneCalls,
                  !self.manualMonitoringOverride,
                  self.phase == .listening,
                  !self.callActivity.shouldMonitor else { return }

            self.stopCaptureEngine()
            self.phase = .waitingForCall
            self.resetLiveIndicators()
        }
        automaticSleepWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: workItem)
    }

    private func cancelAutomaticSleep() {
        automaticSleepWorkItem?.cancel()
        automaticSleepWorkItem = nil
    }

    private func resetLiveIndicators() {
        isLoud = false
        voiceDetected = false
        soundDetected = false
        mouthActivity = 0
        relativeDecibels = 0
        meterProgress = 0.18
        overlayController.hide()
    }

    private func consume(_ frame: LevelFrame) {
        guard phase == .listening || phase == .calibrating else { return }
        updateMouthActivity(decibelsFS: frame.decibelsFS)

        if phase == .calibrating {
            calibration.append(decibelsFS: frame.decibelsFS)
            calibrationFrameCount = calibration.frameCount
            calibrationSignalFrameCount = calibration.signalFrameCount
            currentInputDecibelsFS = frame.decibelsFS
            meterProgress = min(max(Double((frame.decibelsFS + 55) / 45), 0.04), 1)
            voiceDetected = frame.decibelsFS > CalibrationAccumulator.signalFloorDecibelsFS
            return
        }

        if frame.hasSpeechClassification {
            if frame.speechConfidence >= 0.14 {
                speechHold = 1.2
            } else {
                speechHold = max(0, speechHold - frame.duration)
            }
        }
        voiceDetected = !settings.voiceFocus
            || !frame.hasSpeechClassification
            || speechHold > 0

        processor.thresholdDecibels = Float(settings.thresholdDecibels)
        processor.alertDelay = settings.alertDelay
        let reading = processor.process(
            decibelsFS: frame.decibelsFS,
            isSpeech: voiceDetected,
            duration: frame.duration
        )
        relativeDecibels = reading.relativeDecibels
        meterProgress = reading.meterProgress

        if isLoud != reading.isLoud {
            isLoud = reading.isLoud
            if isLoud && settings.showOverlay {
                overlayController.show()
            } else {
                overlayController.hide()
            }
        } else if !settings.showOverlay {
            overlayController.hide()
        }
    }

    private var warningThresholdDecibels: Float {
        max(1.5, Float(settings.thresholdDecibels) * 0.55)
    }

    private func applySettings(
        thresholdDecibels: Double,
        alertDelay: Double,
        showOverlay: Bool
    ) {
        processor.thresholdDecibels = Float(thresholdDecibels)
        processor.alertDelay = alertDelay
        if !showOverlay {
            overlayController.hide()
        }
        objectWillChange.send()
    }

    private func updateMouthActivity(decibelsFS: Float) {
        let baseline = settings.baselineDecibelsFS ?? -36
        let detectionFloor = phase == .calibrating
            ? CalibrationAccumulator.signalFloorDecibelsFS
            : baseline - 14
        let activeSpan = phase == .calibrating
            ? Float(68)
            : Float(settings.thresholdDecibels) + 18
        soundDetected = decibelsFS > detectionFloor
        guard soundDetected else {
            mouthActivity = 0
            return
        }
        mouthActivity = min(
            max(Double((decibelsFS - detectionFloor) / activeSpan), 0),
            1
        )
    }

    private func startCalibrationTimer() {
        calibrationTimeline.start(at: ProcessInfo.processInfo.systemUptime)
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCalibrationClock()
            }
        }
        calibrationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateCalibrationClock() {
        guard phase == .calibrating else {
            stopCalibrationTimer()
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        calibrationProgress = calibrationTimeline.progress(at: now)
        if calibrationTimeline.isFinished(at: now) {
            finishCalibration()
        }
    }

    private func finishCalibration() {
        stopCalibrationTimer()
        calibrationProgress = 1

        guard let baseline = calibration.result else {
            if calibration.frameCount == 0 {
                phase = .error(
                    "The microphone opened, but no audio frames arrived. Quit any other copies of LoudMouth, then try again."
                )
            } else if calibration.signalFrameCount == 0 {
                phase = .error(
                    "Audio frames arrived, but they contained no microphone signal. Check the selected input in System Settings, then try again."
                )
            } else {
                phase = .error(
                    "I received only a moment of microphone signal. Keep talking for the full eight seconds and try again."
                )
            }
            stopCaptureEngine()
            return
        }

        settings.baselineDecibelsFS = baseline
        processor.reset(baselineDecibelsFS: baseline)
        if settings.monitorOnlyDuringHeadphoneCalls {
            stopCaptureEngine()
            resumeConfiguredMonitoring()
        } else {
            phase = .listening
        }
    }

    private func stopCalibrationTimer() {
        calibrationTimer?.invalidate()
        calibrationTimer = nil
    }
}
