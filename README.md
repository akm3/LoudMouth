# LoudMouth

LoudMouth is a private, native macOS menu-bar app that helps you notice when
headphones are making you speak more loudly than usual.

It learns your natural voice level during a short calibration, then animates a
small mouth in the menu bar: green when you are quiet, yellow when you are
getting louder, and red when you have crossed your personal threshold.

> LoudMouth measures change from your own baseline in dBFS. It is deliberately
> not presented as a certified sound-pressure-level or dBA meter.

## What it does

- Uses the Mac’s microphone to measure live voice level on-device.
- Guides you through an eight-second personal calibration.
- Provides a menu-bar status icon and a brief visual reminder when you are too
  loud.
- Lets you adjust sensitivity so yellow and red arrive sooner or later.
- Lets you choose the microphone used for loudness monitoring; the Mac’s
  built-in microphone is the default.
- Sleeps when you are not on a headphone call, then resumes monitoring when a
  local call-activity signal is present.
- Can launch automatically when you sign in to your Mac.

## Privacy, by construction

LoudMouth is designed to make the smallest possible privacy claim and enforce
it in the shipped app:

- Microphone samples are measured only in volatile memory and immediately
  discarded.
- Audio is never recorded, saved, transcribed, uploaded, or sent over a
  network.
- There are no accounts, analytics, ads, crash-reporting SDKs, or third-party
  dependencies.
- Headphone-call detection reads only local Core Audio device, route, and
  activity metadata. It never opens, records, or inspects another app’s call
  audio.
- The app sandbox grants microphone input and nothing else: no incoming or
  outgoing network entitlement, and no user-file access entitlement.
- The only saved values are your numeric dBFS calibration baseline and app
  preferences in `UserDefaults`.
- `PrivacyInfo.xcprivacy` declares zero tracking and zero collected data types.

Every Xcode build runs `scripts/verify_privacy.sh`, which fails if prohibited
networking, recording, transcription, analytics APIs, or entitlements appear.
`scripts/audit_release.sh` audits the final signed app’s entitlements, linked
frameworks, symbols, privacy manifest, and signature.

## Get started

1. Open `LoudMouth.xcodeproj` in Xcode.
2. Choose the **LoudMouth** scheme and **My Mac**, then run the app.
3. Grant microphone access and complete the eight-second voice calibration.
4. Click the mouth in the menu bar to see your current level, pause monitoring,
   recalibrate, or open Settings.

LoudMouth’s Settings window is intentionally compact:

- **Quit LoudMouth** is in the header for quick access.
- **Launch LoudMouth at login** uses macOS’s native login-item service. It
  reflects the actual macOS registration state rather than a saved preference.
- **Startup & energy** controls the headphone-call-aware monitoring mode.
- **Voice reminders** controls sensitivity: moving right reaches yellow and red
  sooner.
- **Microphone & calibration** lets you choose any available input for
  loudness monitoring, shows the active input, and lets you reset your
  baseline.
- The full privacy guarantee stays visible at the bottom of the window.

## Energy-aware monitoring

By default, LoudMouth does not keep the microphone open all day. It waits until
headphones are connected and another app’s active microphone input indicates a
call. It stops capture when that call activity ends, with a short grace period
to avoid flapping between states.

This check is event-driven and local. LoudMouth reads only device type, route,
and process activity flags—not call audio. **Monitor Now** is available as a
manual override, and the Energy setting can restore continuous monitoring.

## Calibration and reliability

Calibration uses a monotonic eight-second timer, so progress remains accurate
if Core Audio changes buffer sizes or briefly stalls. The setup screen shows the
live input level and distinguishes between no microphone frames and a signal
that is simply too quiet.

Microphone startup runs on a dedicated control queue with a watchdog, preventing
a stalled audio-device connection from freezing the interface. LoudMouth binds
the selected microphone through AVFoundation’s capture-device API and receives
PCM sample buffers directly.

## Build and test

```sh
xcodebuild -project LoudMouth.xcodeproj -scheme LoudMouth \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

xcodebuild -project LoudMouth.xcodeproj -scheme LoudMouth \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test

./scripts/verify_privacy.sh
./scripts/audit_release.sh /path/to/LoudMouth.app
```

LoudMouth requires macOS 14 or later and uses SwiftUI, AppKit, AVFoundation,
Core Audio, and ServiceManagement—no cross-platform UI framework.
