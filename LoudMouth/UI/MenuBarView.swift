import AppKit
import SwiftUI

struct StatusItemLabel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        MouthStatusIcon(
            state: model.menuMouthState,
            activity: model.mouthActivity
        )
            .frame(width: 24, height: 17)
            .accessibilityLabel(accessibilityLabel)
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

struct MouthStatusIcon: View {
    let state: MenuMouthState
    let activity: Double

    var body: some View {
        GeometryReader { geometry in
            let outerOpenness = state == .loud
                ? geometry.size.height * 0.92
                : openness

            ZStack {
                MouthShape(openness: outerOpenness, widthFactor: widthFactor)
                    .fill(tint.opacity(state == .idle ? 0.14 : 0.22))
                MouthShape(openness: outerOpenness, widthFactor: widthFactor)
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                if state == .loud {
                    MouthShape(
                        openness: geometry.size.height * 0.52,
                        widthFactor: widthFactor * 0.56
                    )
                    .fill(.black.opacity(0.24))
                }
            }
        }
        .animation(.easeOut(duration: 0.09), value: openness)
        .animation(.smooth(duration: 0.22), value: state)
    }

    private var openness: CGFloat {
        switch state {
        case .idle:
            return 0.8
        case .quiet:
            return 1.4 + CGFloat(activity) * 1.6
        case .elevated:
            return 6.0 + CGFloat(activity) * 4.2
        case .loud:
            return 0
        }
    }

    private var widthFactor: CGFloat {
        switch state {
        case .idle, .quiet: return 0.94
        case .elevated: return 0.70
        case .loud: return 0.68
        }
    }

    private var tint: Color {
        switch state {
        case .idle: return Color.primary.opacity(0.82)
        case .quiet: return Color(red: 0.18, green: 0.72, blue: 0.34)
        case .elevated: return Color(red: 0.96, green: 0.76, blue: 0.03)
        case .loud: return .red
        }
    }
}

private struct MouthShape: Shape {
    var openness: CGFloat
    var widthFactor: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(openness, widthFactor) }
        set {
            openness = newValue.first
            widthFactor = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let width = rect.width * widthFactor
        let left = rect.midX - width / 2
        let right = rect.midX + width / 2
        let middle = rect.midY
        let halfHeight = min(openness / 2, rect.height * 0.46)

        var path = Path()
        path.move(to: CGPoint(x: left, y: middle))
        path.addCurve(
            to: CGPoint(x: right, y: middle),
            control1: CGPoint(x: left + width * 0.25, y: middle - halfHeight),
            control2: CGPoint(x: left + width * 0.72, y: middle - halfHeight)
        )
        path.addCurve(
            to: CGPoint(x: left, y: middle),
            control1: CGPoint(x: left + width * 0.72, y: middle + halfHeight),
            control2: CGPoint(x: left + width * 0.25, y: middle + halfHeight)
        )
        path.closeSubpath()
        return path
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)

            Group {
                switch model.phase {
                case .needsPermission:
                    PermissionView(isDenied: false)
                case .permissionDenied:
                    PermissionView(isDenied: true)
                case .readyToCalibrate:
                    ReadyToCalibrateView()
                case .calibrating:
                    CalibrationView()
                case .listening, .waitingForCall, .paused:
                    MonitoringView()
                case .error(let message):
                    ErrorView(message: message)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 372)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.primary.opacity(0.07))
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("LoudMouth")
                    .font(.system(size: 14, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("LoudMouth Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var headerSubtitle: String {
        switch model.phase {
        case .listening, .calibrating:
            return model.inputDeviceName
        case .waitingForCall:
            return "Sleeping · Waiting for a call"
        case .paused:
            return "Monitoring paused"
        default:
            return "A calmer voice on calls"
        }
    }
}

private struct PermissionView: View {
    @EnvironmentObject private var model: AppModel
    let isDenied: Bool

    var body: some View {
        VStack(spacing: 20) {
            HeroSymbol(
                symbol: isDenied ? "mic.slash.fill" : "waveform.circle.fill",
                tint: isDenied ? .orange : .accentColor
            )

            VStack(spacing: 8) {
                Text(isDenied ? "Microphone access is off" : "Keep your voice in the room")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(isDenied
                     ? "Allow LoudMouth in Privacy & Security so it can measure your voice."
                     : "LoudMouth gently lets you know when headphones make you speak above your natural level.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 298)
            }

            Button(isDenied ? "Open Microphone Settings" : "Allow Microphone") {
                isDenied ? model.openMicrophoneSettings() : model.requestMicrophoneAccess()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if isDenied {
                Button("I’ve enabled it") { model.requestMicrophoneAccess() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            PrivacyNote()
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 24)
    }
}

private struct ReadyToCalibrateView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            HeroSymbol(symbol: "person.wave.2.fill", tint: .accentColor)

            VStack(spacing: 8) {
                Text("Find your natural level")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Put on your headphones, then speak naturally for eight seconds — as if you’re already on a call.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 300)
            }

            Button("Start Calibration") {
                model.beginCalibration()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            PrivacyNote()
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 24)
    }
}

private struct CalibrationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 22) {
            LevelOrb(
                progress: model.meterProgress,
                relativeDecibels: nil,
                tint: .accentColor,
                isActive: model.voiceDetected
            )

            VStack(spacing: 7) {
                Text("Speak naturally")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text("Tell me what you did today, or read a few lines aloud.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ProgressView(value: model.calibrationProgress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                HStack {
                    Text("LEARNING YOUR VOICE")
                    Spacer()
                    Text("\(Int(ceil((1 - model.calibrationProgress) * 8))) SEC")
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 286)

            Button("Cancel") { model.cancelCalibration() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 22)
    }
}

private struct MonitoringView: View {
    @EnvironmentObject private var model: AppModel

    private var isPaused: Bool { model.phase == .paused }
    private var isWaiting: Bool { model.phase == .waitingForCall }
    private var isInactive: Bool { isPaused || isWaiting }

    var body: some View {
        VStack(spacing: 20) {
            LevelOrb(
                progress: isInactive ? 0.18 : model.meterProgress,
                relativeDecibels: isInactive ? nil : model.relativeDecibels,
                tint: tint,
                isActive: !isInactive && model.voiceDetected,
                inactiveLabel: isWaiting ? "ASLEEP" : (isPaused ? "PAUSED" : nil)
            )

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)
            }

            RelativeMeter(
                progress: isInactive ? 0 : model.meterProgress,
                thresholdPosition: 0.70,
                tint: tint
            )

            HStack(spacing: 10) {
                Button {
                    model.toggleMonitoring()
                } label: {
                    Label(primaryButtonTitle, systemImage: primaryButtonSymbol)
                        .frame(minWidth: 74)
                }
                .buttonStyle(.borderedProminent)

                Button("Recalibrate") { model.beginCalibration() }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)

            PrivacyNote()
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .animation(.smooth(duration: 0.3), value: model.phase)
    }

    private var title: String {
        if isWaiting { return model.waitingTitle }
        if isPaused { return "Taking a break" }
        return model.statusTitle
    }

    private var detail: String {
        if isWaiting { return model.waitingDetail }
        if isPaused { return "Resume whenever you’re ready." }
        return model.statusDetail
    }

    private var primaryButtonTitle: String {
        if isWaiting { return "Monitor Now" }
        return isPaused ? "Resume" : "Pause"
    }

    private var primaryButtonSymbol: String {
        if isWaiting { return "play.fill" }
        return isPaused ? "play.fill" : "pause.fill"
    }

    private var tint: Color {
        if model.isLoud { return .red }
        if model.isElevated {
            return .orange
        }
        return .mint
    }
}

private struct ErrorView: View {
    @EnvironmentObject private var model: AppModel
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            HeroSymbol(symbol: "exclamationmark.triangle.fill", tint: .orange)
            VStack(spacing: 7) {
                Text("Let’s try that again")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 290)
            }
            Button("Calibrate Again") { model.beginCalibration() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 30)
    }
}

private struct HeroSymbol: View {
    let symbol: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.10))
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .frame(width: 84, height: 84)
    }
}

private struct PrivacyNote: View {
    var body: some View {
        VStack(spacing: 4) {
            Label("Never recorded · No internet access", systemImage: "lock.fill")
                .font(.system(size: 10.5))

            Text("© 2026 Allen Monroe")
                .font(.system(size: 9.5))

            Text(versionText)
                .font(.system(size: 9.5))
                .monospacedDigit()
        }
        .foregroundStyle(.tertiary)
    }

    private var versionText: String {
        #if SNAPSHOT
        if let snapshotVersion = ProcessInfo.processInfo.environment["LOUDMOUTH_SNAPSHOT_VERSION"] {
            return snapshotVersion
        }
        #endif

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String

        if let build, !build.isEmpty {
            return "Version \(version) (\(build))"
        }
        return "Version \(version)"
    }
}
