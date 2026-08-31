import XCTest
@testable import LoudMouth

final class HeadphoneCallMonitorTests: XCTestCase {
    func testProcessDetectionRequiresBothHeadphonesAndAnotherMicrophoneUser() {
        let withoutHeadphones = HeadphoneCallActivity(
            headphonesAvailable: false,
            headphoneName: nil,
            anotherProcessIsUsingMicrophone: true,
            headphoneAudioIsRunning: true,
            supportsProcessDetection: true
        )
        let headphonesWithoutCall = HeadphoneCallActivity(
            headphonesAvailable: true,
            headphoneName: "AirPods",
            anotherProcessIsUsingMicrophone: false,
            headphoneAudioIsRunning: true,
            supportsProcessDetection: true
        )
        let headphoneCall = HeadphoneCallActivity(
            headphonesAvailable: true,
            headphoneName: "AirPods",
            anotherProcessIsUsingMicrophone: true,
            headphoneAudioIsRunning: true,
            supportsProcessDetection: true
        )

        XCTAssertFalse(withoutHeadphones.shouldMonitor)
        XCTAssertFalse(headphonesWithoutCall.shouldMonitor)
        XCTAssertTrue(headphoneCall.shouldMonitor)
    }

    func testLegacyFallbackRequiresActiveHeadphoneAudio() {
        let idleHeadphones = HeadphoneCallActivity(
            headphonesAvailable: true,
            headphoneName: "USB Headset",
            anotherProcessIsUsingMicrophone: false,
            headphoneAudioIsRunning: false,
            supportsProcessDetection: false
        )
        let activeHeadphones = HeadphoneCallActivity(
            headphonesAvailable: true,
            headphoneName: "USB Headset",
            anotherProcessIsUsingMicrophone: false,
            headphoneAudioIsRunning: true,
            supportsProcessDetection: false
        )

        XCTAssertFalse(idleHeadphones.shouldMonitor)
        XCTAssertTrue(activeHeadphones.shouldMonitor)
    }
}
