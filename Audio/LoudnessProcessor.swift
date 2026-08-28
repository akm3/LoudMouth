import Foundation

struct LevelFrame: Sendable {
    let decibelsFS: Float
    let duration: TimeInterval
    let speechConfidence: Float
    let hasSpeechClassification: Bool
}

struct CalibrationTimeline: Equatable {
    static let duration: TimeInterval = 8

    private(set) var startedAt: TimeInterval?

    mutating func start(at time: TimeInterval) {
        startedAt = time
    }

    func progress(at time: TimeInterval) -> Double {
        guard let startedAt else { return 0 }
        return min(max((time - startedAt) / Self.duration, 0), 1)
    }

    func isFinished(at time: TimeInterval) -> Bool {
        progress(at: time) >= 1
    }
}

struct LoudnessReading: Equatable {
    let smoothedDecibelsFS: Float
    let relativeDecibels: Float
    let meterProgress: Double
    let isLoud: Bool
}

struct LoudnessProcessor {
    var baselineDecibelsFS: Float
    var thresholdDecibels: Float
    var alertDelay: TimeInterval

    private(set) var smoothedDecibelsFS: Float = -60
    private(set) var isLoud = false
    private var timeAboveThreshold: TimeInterval = 0
    private var timeBelowReset: TimeInterval = 0

    init(
        baselineDecibelsFS: Float,
        thresholdDecibels: Float,
        alertDelay: TimeInterval
    ) {
        self.baselineDecibelsFS = baselineDecibelsFS
        self.thresholdDecibels = thresholdDecibels
        self.alertDelay = alertDelay
        smoothedDecibelsFS = baselineDecibelsFS
    }

    mutating func process(
        decibelsFS: Float,
        isSpeech: Bool,
        duration: TimeInterval
    ) -> LoudnessReading {
        let coefficient: Float = decibelsFS > smoothedDecibelsFS ? 0.34 : 0.10
        smoothedDecibelsFS += (decibelsFS - smoothedDecibelsFS) * coefficient

        let relative = smoothedDecibelsFS - baselineDecibelsFS
        if isSpeech && relative >= thresholdDecibels {
            timeAboveThreshold += duration
            timeBelowReset = 0
            if timeAboveThreshold >= alertDelay {
                isLoud = true
            }
        } else {
            timeAboveThreshold = max(0, timeAboveThreshold - duration * 1.7)
            if relative < thresholdDecibels - 2 || !isSpeech {
                timeBelowReset += duration
                if timeBelowReset >= 0.4 {
                    isLoud = false
                }
            }
        }

        let progress = Double((relative + 8) / (thresholdDecibels + 10))
        return LoudnessReading(
            smoothedDecibelsFS: smoothedDecibelsFS,
            relativeDecibels: relative,
            meterProgress: min(max(progress, 0), 1),
            isLoud: isLoud
        )
    }

    mutating func reset(baselineDecibelsFS: Float? = nil) {
        if let baselineDecibelsFS {
            self.baselineDecibelsFS = baselineDecibelsFS
        }
        smoothedDecibelsFS = self.baselineDecibelsFS
        timeAboveThreshold = 0
        timeBelowReset = 0
        isLoud = false
    }

    static func decibelsFS(samples: UnsafePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return -80 }
        var sum: Float = 0
        for index in 0..<count {
            let sample = samples[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        return max(-80, 20 * log10(max(rms, 0.000_000_1)))
    }

    static func loudestChannelDecibelsFS(
        channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameCount: Int
    ) -> Float {
        guard channelCount > 0, frameCount > 0 else { return -80 }

        // dBFS readings are zero or negative. Starting at zero would make every
        // real microphone frame look clipped and calibration would reject it.
        var loudest: Float = -80
        for channel in 0..<channelCount {
            let level = decibelsFS(samples: channels[channel], count: frameCount)
            loudest = max(loudest, level)
        }
        return loudest
    }
}

struct CalibrationAccumulator {
    static let signalFloorDecibelsFS: Float = -79

    private(set) var samples: [Float] = []
    private(set) var frameCount = 0
    private(set) var peakDecibelsFS: Float = -80

    mutating func append(decibelsFS: Float) {
        frameCount += 1
        guard decibelsFS.isFinite else { return }
        peakDecibelsFS = max(peakDecibelsFS, decibelsFS)

        // Microphone gain varies significantly between Macs and input devices.
        // Keep every real (non-digital-silence), non-clipped frame rather than
        // rejecting softly captured speech with an arbitrary loudness cutoff.
        guard decibelsFS > Self.signalFloorDecibelsFS, decibelsFS < -1 else { return }
        samples.append(decibelsFS)
    }

    var signalFrameCount: Int {
        samples.count
    }

    var result: Float? {
        // Even a 24 kHz input produces far more than eight tap callbacks during
        // calibration. Eight usable frames accepts brief device reconfiguration
        // without mistaking one transient for a personal voice baseline.
        guard samples.count >= 8 else { return nil }
        let sorted = samples.sorted()
        let index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.68))
        return sorted[index]
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        frameCount = 0
        peakDecibelsFS = -80
    }
}
