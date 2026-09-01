import Foundation

enum SensitivityScale {
    static let leastSensitiveThreshold = 10.0
    static let mostSensitiveThreshold = 3.0
    static let defaultThreshold = 5.0

    static func sensitivity(for thresholdDecibels: Double) -> Double {
        let range = leastSensitiveThreshold - mostSensitiveThreshold
        return min(max((leastSensitiveThreshold - thresholdDecibels) / range, 0), 1)
    }

    static func thresholdDecibels(for sensitivity: Double) -> Double {
        let clamped = min(max(sensitivity, 0), 1)
        return leastSensitiveThreshold
            - clamped * (leastSensitiveThreshold - mostSensitiveThreshold)
    }
}

final class AppSettings: ObservableObject {
    private enum Key {
        static let threshold = "thresholdDecibels"
        static let thresholdTuningVersion = "thresholdTuningVersion"
        static let alertDelay = "alertDelay"
        static let voiceFocus = "voiceFocus"
        static let showOverlay = "showOverlay"
        static let preferBuiltIn = "preferBuiltInMicrophone"
        static let preferredMicrophoneUID = "preferredMicrophoneUID"
        static let monitorOnlyDuringHeadphoneCalls = "monitorOnlyDuringHeadphoneCalls"
        static let baseline = "baselineDecibelsFS"
    }

    private let defaults: UserDefaults

    @Published var thresholdDecibels: Double {
        didSet { defaults.set(thresholdDecibels, forKey: Key.threshold) }
    }

    var sensitivity: Double {
        get { SensitivityScale.sensitivity(for: thresholdDecibels) }
        set { thresholdDecibels = SensitivityScale.thresholdDecibels(for: newValue) }
    }

    var sensitivityLabel: String {
        if sensitivity >= 0.67 { return "High" }
        if sensitivity >= 0.34 { return "Medium" }
        return "Low"
    }
    @Published var alertDelay: Double {
        didSet { defaults.set(alertDelay, forKey: Key.alertDelay) }
    }
    @Published var voiceFocus: Bool {
        didSet { defaults.set(voiceFocus, forKey: Key.voiceFocus) }
    }
    @Published var showOverlay: Bool {
        didSet { defaults.set(showOverlay, forKey: Key.showOverlay) }
    }
    @Published var preferredMicrophoneUID: String? {
        didSet {
            if let preferredMicrophoneUID {
                defaults.set(preferredMicrophoneUID, forKey: Key.preferredMicrophoneUID)
            } else {
                defaults.removeObject(forKey: Key.preferredMicrophoneUID)
            }
        }
    }
    @Published var monitorOnlyDuringHeadphoneCalls: Bool {
        didSet {
            defaults.set(
                monitorOnlyDuringHeadphoneCalls,
                forKey: Key.monitorOnlyDuringHeadphoneCalls
            )
        }
    }
    @Published var baselineDecibelsFS: Float? {
        didSet {
            if let baselineDecibelsFS {
                defaults.set(baselineDecibelsFS, forKey: Key.baseline)
            } else {
                defaults.removeObject(forKey: Key.baseline)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedThreshold = defaults.object(forKey: Key.threshold) == nil
            ? SensitivityScale.defaultThreshold
            : defaults.double(forKey: Key.threshold)
        let selectedThreshold: Double
        if defaults.integer(forKey: Key.thresholdTuningVersion) < 2 {
            // Previous builds defaulted to +8 dB, which made red require a
            // near-yell. Preserve more-sensitive choices while lowering the
            // old tuning for everyone else.
            selectedThreshold = min(storedThreshold, SensitivityScale.defaultThreshold)
            defaults.set(2, forKey: Key.thresholdTuningVersion)
            defaults.set(selectedThreshold, forKey: Key.threshold)
        } else {
            selectedThreshold = storedThreshold
        }
        thresholdDecibels = selectedThreshold
        alertDelay = defaults.object(forKey: Key.alertDelay) == nil
            ? 0.65 : defaults.double(forKey: Key.alertDelay)
        voiceFocus = defaults.object(forKey: Key.voiceFocus) == nil
            ? true : defaults.bool(forKey: Key.voiceFocus)
        showOverlay = defaults.object(forKey: Key.showOverlay) == nil
            ? true : defaults.bool(forKey: Key.showOverlay)
        if let savedMicrophoneUID = defaults.string(forKey: Key.preferredMicrophoneUID) {
            preferredMicrophoneUID = savedMicrophoneUID
        } else if defaults.object(forKey: Key.preferBuiltIn) != nil,
                  !defaults.bool(forKey: Key.preferBuiltIn),
                  let defaultInputID = AudioInputDevices.defaultInputID {
            // Preserve the previous "use the Mac default" choice during the
            // transition from the old built-in microphone toggle.
            preferredMicrophoneUID = AudioInputDevices.all().first(where: {
                $0.id == defaultInputID
            })?.uid
        } else {
            // No stored choice means built-in, selected by the capture layer.
            preferredMicrophoneUID = nil
        }
        monitorOnlyDuringHeadphoneCalls = defaults.object(
            forKey: Key.monitorOnlyDuringHeadphoneCalls
        ) == nil
            ? true
            : defaults.bool(forKey: Key.monitorOnlyDuringHeadphoneCalls)
        baselineDecibelsFS = defaults.object(forKey: Key.baseline) == nil
            ? nil : defaults.float(forKey: Key.baseline)
    }
}
