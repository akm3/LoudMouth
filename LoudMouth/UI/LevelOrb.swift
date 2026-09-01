import SwiftUI

struct LevelOrb: View {
    let progress: Double
    let relativeDecibels: Float?
    let tint: Color
    let isActive: Bool
    var inactiveLabel: String? = nil

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(isActive ? 0.13 : 0.07))
                .blur(radius: 13)
                .scaleEffect(1.05 + progress * 0.08)

            Circle()
                .fill(.thinMaterial)
                .overlay {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [tint.opacity(0.16), tint.opacity(0.035), .clear],
                                center: .center,
                                startRadius: 2,
                                endRadius: 70
                            )
                        )
                }
                .overlay {
                    Circle()
                        .stroke(.primary.opacity(0.07), lineWidth: 1)
                }

            Circle()
                .trim(from: 0, to: max(0.025, progress))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.38), tint, tint.opacity(0.7)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(4)

            VStack(spacing: 7) {
                WaveformGlyph(progress: progress, tint: tint, isActive: isActive)
                if let relativeDecibels {
                    Text(relativeText(relativeDecibels))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(relativeDecibels)))
                } else {
                    Text(inactiveLabel ?? (isActive ? "I CAN HEAR YOU" : "SPEAK NOW"))
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                }
            }
            .foregroundStyle(tint)
        }
        .frame(width: 150, height: 150)
        .animation(.smooth(duration: 0.26), value: progress)
        .animation(.smooth(duration: 0.3), value: tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            inactiveLabel
                ?? relativeDecibels.map { "Voice level \(relativeText($0))" }
                ?? "Voice calibration"
        )
    }

    private func relativeText(_ value: Float) -> String {
        if abs(value) < 0.75 { return "BASELINE" }
        return String(format: "%+.0f dB", value)
    }
}

private struct WaveformGlyph: View {
    let progress: Double
    let tint: Color
    let isActive: Bool

    private let shape: [Double] = [0.35, 0.62, 0.84, 0.52, 1.0, 0.68, 0.42]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(shape.enumerated()), id: \.offset) { _, scale in
                Capsule()
                    .fill(tint)
                    .frame(
                        width: 3,
                        height: 5 + 24 * scale * (isActive ? max(progress, 0.26) : 0.18)
                    )
            }
        }
        .frame(height: 31)
    }
}

struct RelativeMeter: View {
    let progress: Double
    @Binding var sensitivity: Double
    let tint: Color
    @State private var isAdjustingSensitivity = false

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.07))
                    LinearGradient(
                        colors: [.mint.opacity(0.75), .orange.opacity(0.9), .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .mask(alignment: .leading) {
                        HStack(spacing: 0) {
                            Rectangle()
                                .frame(width: max(8, geometry.size.width * progress))
                            Spacer(minLength: 0)
                        }
                    }
                    .clipShape(Capsule())

                    Circle()
                        .fill(.black.opacity(0.82))
                        .overlay(Circle().stroke(.white.opacity(0.48), lineWidth: 1))
                        .frame(width: 11, height: 11)
                        .offset(x: geometry.size.width * sensitivity - 5.5)
                        .scaleEffect(isAdjustingSensitivity ? 1.22 : 1)
                        .shadow(color: .black.opacity(0.22), radius: 1.5, y: 0.5)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isAdjustingSensitivity = true
                            sensitivity = position(for: value.location.x, width: geometry.size.width)
                        }
                        .onEnded { _ in
                            isAdjustingSensitivity = false
                        }
                )
            }
            .frame(height: 9)

            HStack {
                Text("NATURAL")
                Spacer()
                Text("REMINDER")
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: 286)
        .animation(.smooth(duration: 0.25), value: progress)
        .animation(.smooth(duration: 0.14), value: sensitivity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Voice level and reminder sensitivity")
        .accessibilityValue("\(Int(progress * 100)) percent voice level, \(sensitivityLabel) sensitivity")
        .accessibilityHint("Drag the black marker right to receive reminders sooner.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                sensitivity = min(sensitivity + 0.05, 1)
            case .decrement:
                sensitivity = max(sensitivity - 0.05, 0)
            @unknown default:
                break
            }
        }
    }

    private var sensitivityLabel: String {
        if sensitivity >= 0.67 { return "high" }
        if sensitivity >= 0.34 { return "medium" }
        return "low"
    }

    private func position(for horizontalLocation: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return sensitivity }
        return min(max(horizontalLocation / width, 0), 1)
    }
}
