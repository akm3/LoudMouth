import XCTest
@testable import LoudMouth

final class LoudnessProcessorTests: XCTestCase {
    func testCalibrationTimelineRunsForEightSeconds() {
        var timeline = CalibrationTimeline()
        timeline.start(at: 100)

        XCTAssertEqual(timeline.progress(at: 100), 0, accuracy: 0.0001)
        XCTAssertEqual(timeline.progress(at: 101), 0.125, accuracy: 0.0001)
        XCTAssertEqual(timeline.progress(at: 104), 0.5, accuracy: 0.0001)
        XCTAssertEqual(timeline.progress(at: 107.92), 0.99, accuracy: 0.0001)
        XCTAssertFalse(timeline.isFinished(at: 107.99))
        XCTAssertEqual(timeline.progress(at: 108), 1, accuracy: 0.0001)
        XCTAssertTrue(timeline.isFinished(at: 108))
    }

    func testDecibelConversion() {
        let fullScale = [Float](repeating: 1, count: 128)
        let tenthScale = [Float](repeating: 0.1, count: 128)

        let fullDB = fullScale.withUnsafeBufferPointer {
            LoudnessProcessor.decibelsFS(samples: $0.baseAddress!, count: $0.count)
        }
        let tenthDB = tenthScale.withUnsafeBufferPointer {
            LoudnessProcessor.decibelsFS(samples: $0.baseAddress!, count: $0.count)
        }

        XCTAssertEqual(fullDB, 0, accuracy: 0.001)
        XCTAssertEqual(tenthDB, -20, accuracy: 0.01)
    }

    func testLoudestChannelStartsBelowZeroDBFS() {
        var quiet = [Float](repeating: 0.01, count: 128)
        var voice = [Float](repeating: 0.1, count: 128)

        let measured = quiet.withUnsafeMutableBufferPointer { quietBuffer in
            voice.withUnsafeMutableBufferPointer { voiceBuffer in
                let channels = [quietBuffer.baseAddress!, voiceBuffer.baseAddress!]
                return channels.withUnsafeBufferPointer { channelBuffer in
                    LoudnessProcessor.loudestChannelDecibelsFS(
                        channels: channelBuffer.baseAddress!,
                        channelCount: channelBuffer.count,
                        frameCount: 128
                    )
                }
            }
        }

        XCTAssertEqual(measured, -20, accuracy: 0.01)
        XCTAssertLessThan(measured, -2, "Conversational audio must not look clipped")
    }

    func testCalibrationUsesConversationalUpperMiddle() {
        var calibration = CalibrationAccumulator()
        for value in stride(from: -34.0, through: -22.0, by: 0.5) {
            calibration.append(decibelsFS: Float(value))
        }
        calibration.append(decibelsFS: -1)   // clipped transient is ignored
        calibration.append(decibelsFS: -75)  // silence is ignored

        XCTAssertNotNil(calibration.result)
        XCTAssertEqual(calibration.result!, -26, accuracy: 1.0)
    }

    func testCalibrationAcceptsVeryQuietMicrophoneGain() {
        var calibration = CalibrationAccumulator()
        for index in 0..<24 {
            calibration.append(decibelsFS: -72 + Float(index % 5))
        }

        XCTAssertEqual(calibration.frameCount, 24)
        XCTAssertEqual(calibration.signalFrameCount, 24)
        XCTAssertNotNil(calibration.result)
        XCTAssertEqual(calibration.result!, -69, accuracy: 1.0)
    }

    func testCalibrationRejectsOnlyDigitalSilenceAndClipping() {
        var calibration = CalibrationAccumulator()
        for _ in 0..<30 {
            calibration.append(decibelsFS: -80)
        }
        calibration.append(decibelsFS: 0)

        XCTAssertEqual(calibration.frameCount, 31)
        XCTAssertEqual(calibration.signalFrameCount, 0)
        XCTAssertNil(calibration.result)
    }

    func testAlertRequiresSustainedLoudSpeech() {
        var processor = LoudnessProcessor(
            baselineDecibelsFS: -30,
            thresholdDecibels: 8,
            alertDelay: 0.5
        )
        processor.reset()

        var reading: LoudnessReading?
        for _ in 0..<30 {
            reading = processor.process(decibelsFS: -18, isSpeech: true, duration: 0.02)
        }

        XCTAssertEqual(reading?.isLoud, true)
    }

    func testNoiseDoesNotTriggerWhenSpeechGateIsClosed() {
        var processor = LoudnessProcessor(
            baselineDecibelsFS: -30,
            thresholdDecibels: 8,
            alertDelay: 0.3
        )
        processor.reset()

        var reading: LoudnessReading?
        for _ in 0..<40 {
            reading = processor.process(decibelsFS: -12, isSpeech: false, duration: 0.02)
        }

        XCTAssertEqual(reading?.isLoud, false)
    }

    func testDefaultSensitivityReachesRedAtExtraLoudVoiceLevel() {
        var processor = LoudnessProcessor(
            baselineDecibelsFS: -30,
            thresholdDecibels: Float(SensitivityScale.defaultThreshold),
            alertDelay: 0.65
        )

        var reading: LoudnessReading?
        for _ in 0..<100 {
            reading = processor.process(
                decibelsFS: -24,
                isSpeech: true,
                duration: 0.02
            )
        }

        XCTAssertEqual(reading?.isLoud, true)
    }

    func testSensitivitySliderMovesThresholdInExpectedDirection() {
        XCTAssertEqual(SensitivityScale.thresholdDecibels(for: 0), 10, accuracy: 0.001)
        XCTAssertEqual(SensitivityScale.thresholdDecibels(for: 1), 3, accuracy: 0.001)
        XCTAssertGreaterThan(
            SensitivityScale.thresholdDecibels(for: 0.25),
            SensitivityScale.thresholdDecibels(for: 0.75)
        )
    }
}
