# LoudMouth

LoudMouth is a native macOS menu-bar app that learns a person’s natural speaking
level and gives a quiet visual reminder when headphones make them speak louder.

## Product principles

- **Relative, not pretend-precise:** LoudMouth reports change from a personal
  calibration in dBFS. It does not claim that an uncalibrated Mac microphone is
  a certified dBA meter.
- **Private by construction:** Audio is analyzed in memory with Apple’s
  AVFoundation framework. It is never written to disk or sent
  over a network.
- **Native on purpose:** The interface uses SwiftUI inside a direct AppKit
  status item and popover, plus a small AppKit panel for the non-activating
  on-screen reminder. There are no cross-platform UI layers.
- **Energy-aware by default:** Microphone capture stays stopped until headphones
  and another app's active microphone input indicate that a call has begun.

## Run locally

1. Open `LoudMouth.xcodeproj` in Xcode.
2. Select the **LoudMouth** scheme and **My Mac** destination.
3. Run and follow the native welcome window to grant microphone access and
   complete the eight-second calibration.
4. After setup, click the mouth in the menu bar to pause, recalibrate, or adjust
   LoudMouth. Double-clicking the app again reopens the welcome window.

The app prefers the Mac’s built-in microphone, even when headphones are the
default input. This can be changed in Settings.

After calibration, LoudMouth sleeps by default whenever no headphone call is
active. Its event-driven Core Audio observer reads only device type, route, and
process activity flags; it never receives call audio. Monitoring starts as soon
as a qualifying call is detected and stops 15 seconds after the call activity
ends. **Monitor Now** provides a manual override, and the Energy setting can
restore continuous monitoring if desired.

Calibration uses a monotonic eight-second timer, so its progress remains
accurate even if Core Audio changes buffer sizes or briefly stalls delivery.
The setup screen shows the live dBFS input level, accepts genuinely quiet mic
signals, and reports separately when no audio frames or no signal arrive.
Microphone startup runs on a dedicated control queue and has a four-second
watchdog, so a stalled audio-device connection cannot freeze the interface.
LoudMouth binds the selected microphone through AVFoundation's capture-device
API and receives PCM sample buffers directly. This avoids changes to the
system's temporary aggregate audio device from stopping the meter.

Only one LoudMouth version runs at a time. Opening a newer build stops older
copies before they can compete for the microphone; opening an older or matching
copy brings the already-running version forward.

## Privacy architecture

LoudMouth's privacy promise is enforced by the shipped app, not only by policy:

- Microphone buffers are measured in volatile memory and immediately released.
- A lightweight local acoustic gate focuses the meter on voice-like sound; no
  machine-learning model or transcription is used.
- Headphone-call detection uses local Core Audio metadata callbacks only. It
  does not open, inspect, record, or identify the contents of another app's audio.
- The app contains no recorder, audio-file writer, networking, analytics, ads,
  crash-reporting SDK, account system, or third-party dependency.
- The macOS App Sandbox grants microphone input and nothing else. In particular,
  it omits both incoming and outgoing network entitlements and all user-file
  access entitlements.
- The only persisted values are the numeric dBFS calibration baseline and UI
  preferences in `UserDefaults`. Voice and sound data are never persisted.
- `PrivacyInfo.xcprivacy` declares no tracking and no collected data types.

Every Xcode build runs `scripts/verify_privacy.sh`. The build fails if network,
recording, transcription, analytics APIs, or forbidden entitlements appear.
`scripts/audit_release.sh` separately audits the final signed app’s entitlements,
linked frameworks, undefined symbols, privacy manifest, and code signature.

## Test from the command line

```sh
xcodebuild -project LoudMouth.xcodeproj -scheme LoudMouth \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test

./scripts/verify_privacy.sh
./scripts/audit_release.sh /path/to/LoudMouth.app
```
