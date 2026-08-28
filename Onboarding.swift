import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let didShowWelcomeKey = "didShowWelcomeWindowV2"

    private var statusBarController: StatusBarController?
    private var welcomeWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard becomePrimaryLoudMouthInstance() else { return }

        let dependencies = AppDependencies.shared
        statusBarController = StatusBarController(
            model: dependencies.model,
            settings: dependencies.settings
        )

        DispatchQueue.main.async { [weak self] in
            self?.showInitialWelcomeIfNeeded()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showWelcomeWindow()
        return true
    }

    func showInitialWelcomeIfNeeded() {
        let setupIsComplete = AppDependencies.shared.settings.baselineDecibelsFS != nil
        guard !UserDefaults.standard.bool(forKey: Self.didShowWelcomeKey)
                || !setupIsComplete else { return }
        showWelcomeWindow()
    }

    private func showWelcomeWindow() {
        let model = AppDependencies.shared.model

        if welcomeWindowController == nil {
            let rootView = WelcomeView(
                onFinish: { [weak self] in self?.finishWelcome() },
                onSetUpLater: { [weak self] in self?.setUpLater() }
            )
            .environmentObject(model)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 530),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to LoudMouth"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView: rootView)
            welcomeWindowController = NSWindowController(window: window)
        }

        welcomeWindowController?.showWindow(nil)
        welcomeWindowController?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finishWelcome() {
        UserDefaults.standard.set(true, forKey: Self.didShowWelcomeKey)
        welcomeWindowController?.close()
    }

    private func setUpLater() {
        let model = AppDependencies.shared.model
        if model.phase == .calibrating {
            model.cancelCalibration()
        }
        finishWelcome()
    }

    private func becomePrimaryLoudMouthInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return true }

        let currentProcess = NSRunningApplication.current
        let currentVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"
        let otherInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentProcess.processIdentifier }

        guard !otherInstances.isEmpty else { return true }

        // If the already-running copy is the same version or newer, keep it and
        // close this launch. If this is an update, stop only the older copies.
        // That prevents multiple versions from competing for the microphone.
        if let preferredExisting = otherInstances.first(where: { application in
            guard let bundleURL = application.bundleURL,
                  let version = Bundle(url: bundleURL)?.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                  ) as? String else {
                return true
            }
            return version.compare(currentVersion, options: .numeric) != .orderedAscending
        }) {
            preferredExisting.activate(options: [])
            NSApp.terminate(nil)
            return false
        }

        for application in otherInstances {
            // LoudMouth owns no documents or unsaved user data. Force-stopping
            // an older build also recovers one that is stuck inside Core Audio.
            _ = application.forceTerminate()
        }
        return true
    }
}

@MainActor
private final class StatusBarController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var modelUpdates: AnyCancellable?

    init(model: AppModel, settings: AppSettings) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: 31)
        super.init()

        statusItem.autosaveName = "LoudMouthStatusItemV2"
        statusItem.isVisible = true

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
            button.imagePosition = .imageOnly
            button.toolTip = "LoudMouth"
        }

        let content = MenuBarView()
            .environmentObject(model)
            .environmentObject(settings)
        let hostingController = NSHostingController(rootView: content)
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 372, height: 520)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        modelUpdates = model.objectWillChange
            .throttle(
                for: .milliseconds(100),
                scheduler: RunLoop.main,
                latest: true
            )
            .sink { [weak self] _ in
                self?.refreshIcon()
            }

        refreshIcon()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            refreshIcon()
            button.highlight(true)
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        button.image = StatusMouthImage.make(
            state: model.menuMouthState,
            activity: model.mouthActivity
        )
        button.setAccessibilityLabel(accessibilityLabel)
        statusItem.isVisible = true
    }

    private var accessibilityLabel: String {
        if model.phase == .waitingForCall {
            return "LoudMouth: sleeping until a headphone call starts"
        }
        if model.phase == .paused {
            return "LoudMouth: monitoring paused"
        }
        switch model.menuMouthState {
        case .idle: return "LoudMouth: listening for your voice"
        case .quiet: return "LoudMouth: comfortable voice level"
        case .elevated: return "LoudMouth: voice level is elevated"
        case .loud: return "LoudMouth: voice is loud"
        }
    }
}

private enum StatusMouthImage {
    static func make(state: MenuMouthState, activity: Double) -> NSImage {
        let size = NSSize(width: 25, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let properties = properties(for: state, activity: activity)
            let mouthRect = rect.insetBy(dx: 1.5, dy: 1.5)
            let outerOpenness = state == .loud
                ? mouthRect.height * 0.92
                : properties.openness
            let path = mouthPath(
                in: mouthRect,
                openness: outerOpenness,
                widthFactor: properties.widthFactor
            )

            properties.color.withAlphaComponent(state == .idle ? 0.12 : 0.20).setFill()
            path.fill()
            properties.color.setStroke()
            path.lineWidth = 1.8
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()

            if state == .loud {
                let innerRect = rect.insetBy(dx: 5.5, dy: 4.5)
                let inner = mouthPath(
                    in: innerRect,
                    openness: innerRect.height * 0.76,
                    widthFactor: properties.widthFactor * 0.78
                )
                NSColor.black.withAlphaComponent(0.24).setFill()
                inner.fill()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "LoudMouth"
        return image
    }

    private static func properties(
        for state: MenuMouthState,
        activity: Double
    ) -> (openness: CGFloat, widthFactor: CGFloat, color: NSColor) {
        switch state {
        case .idle:
            return (1.2, 0.94, NSColor.labelColor.withAlphaComponent(0.82))
        case .quiet:
            return (
                1.8 + CGFloat(activity) * 1.8,
                0.94,
                NSColor(calibratedRed: 0.10, green: 0.66, blue: 0.28, alpha: 1)
            )
        case .elevated:
            return (
                7.0 + CGFloat(activity) * 4.2,
                0.72,
                NSColor(calibratedRed: 0.92, green: 0.63, blue: 0.00, alpha: 1)
            )
        case .loud:
            return (
                0,
                0.67,
                .systemRed
            )
        }
    }

    private static func mouthPath(
        in rect: NSRect,
        openness: CGFloat,
        widthFactor: CGFloat
    ) -> NSBezierPath {
        let width = rect.width * widthFactor
        let left = rect.midX - width / 2
        let right = rect.midX + width / 2
        let middle = rect.midY
        let halfHeight = min(openness / 2, rect.height * 0.46)

        let path = NSBezierPath()
        path.move(to: NSPoint(x: left, y: middle))
        path.curve(
            to: NSPoint(x: right, y: middle),
            controlPoint1: NSPoint(x: left + width * 0.25, y: middle + halfHeight),
            controlPoint2: NSPoint(x: left + width * 0.72, y: middle + halfHeight)
        )
        path.curve(
            to: NSPoint(x: left, y: middle),
            controlPoint1: NSPoint(x: left + width * 0.72, y: middle - halfHeight),
            controlPoint2: NSPoint(x: left + width * 0.25, y: middle - halfHeight)
        )
        path.close()
        return path
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel

    let onFinish: () -> Void
    let onSetUpLater: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 22) {
                mouthLegend

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 390)
                }

                phaseControls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 42)
            .padding(.top, 38)

            Divider().opacity(0.55)

            HStack(spacing: 9) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("Audio is analyzed only in memory on this Mac — never recorded or sent anywhere.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 520, height: 530)
        .background(.regularMaterial)
    }

    private var mouthLegend: some View {
        HStack(spacing: 16) {
            legendMouth(state: .quiet, activity: 0.32, label: "Comfortable")
            legendMouth(state: .elevated, activity: 0.76, label: "Elevated")
            legendMouth(state: .loud, activity: 1, label: "Too loud")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The menu bar mouth changes from green to yellow to red as your voice gets louder")
    }

    private func legendMouth(
        state: MenuMouthState,
        activity: Double,
        label: String
    ) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.primary.opacity(0.055))
                MouthStatusIcon(state: state, activity: activity)
                    .frame(width: 46, height: 32)
            }
            .frame(width: 70, height: 70)

            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var phaseControls: some View {
        switch model.phase {
        case .needsPermission:
            VStack(spacing: 12) {
                Button("Allow Microphone") {
                    model.requestMicrophoneAccess()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Set Up Later", action: onSetUpLater)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

        case .permissionDenied:
            VStack(spacing: 12) {
                Button("Open Microphone Settings") {
                    model.openMicrophoneSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Set Up Later", action: onSetUpLater)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

        case .readyToCalibrate:
            VStack(spacing: 12) {
                Button("Start 8-Second Calibration") {
                    model.beginCalibration()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Set Up Later", action: onSetUpLater)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

        case .calibrating:
            VStack(spacing: 12) {
                ProgressView(value: model.calibrationProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 280)
                Text("Keep speaking naturally… \(Int(model.calibrationProgress * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                VStack(spacing: 3) {
                    Text(model.calibrationInputStatus)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(model.calibrationSignalFrameCount > 0 ? .green : .secondary)
                    if !model.calibrationInputLevel.isEmpty {
                        Text(model.calibrationInputLevel)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                Button("Cancel", action: model.cancelCalibration)
                    .buttonStyle(.plain)
            }

        case .listening, .waitingForCall:
            Button("Finish Setup", action: onFinish)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

        case .paused:
            Button("Start Monitoring") {
                model.startListening()
                onFinish()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .error:
            VStack(spacing: 12) {
                Button("Try Calibration Again", action: model.beginCalibration)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Set Up Later", action: onSetUpLater)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        switch model.phase {
        case .needsPermission:
            return "LoudMouth lives in your menu bar"
        case .permissionDenied:
            return "Microphone access is off"
        case .readyToCalibrate:
            return "Find your natural voice level"
        case .calibrating:
            return "Speak as if you’re on a call"
        case .listening, .waitingForCall:
            return "You’re all set"
        case .paused:
            return "LoudMouth is ready"
        case .error:
            return "Let’s try that again"
        }
    }

    private var detail: String {
        switch model.phase {
        case .needsPermission:
            return "Look for the small mouth at the top-right of your screen. It opens slightly as you speak, then turns yellow or red when your voice rises."
        case .permissionDenied:
            return "Allow LoudMouth in Privacy & Security so it can measure live sound levels on this Mac."
        case .readyToCalibrate:
            return "Put on your headphones and speak naturally for eight seconds. LoudMouth uses that as your personal baseline."
        case .calibrating:
            return "A few natural sentences are perfect. Nothing you say is stored or transcribed."
        case .listening:
            return "The mouth in your menu bar is now listening. Click it any time to pause, recalibrate, or adjust the reminder."
        case .waitingForCall:
            return "LoudMouth will sleep quietly, then wake automatically when headphones and an active call are detected."
        case .paused:
            return "Start monitoring now, or close this window and use the mouth in your menu bar whenever you’re ready."
        case .error(let message):
            return message
        }
    }
}
