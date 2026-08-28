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
    let thresholdPosition: Double
    let tint: Color

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
                        .fill(.background)
                        .overlay(Circle().stroke(.primary.opacity(0.25), lineWidth: 1))
                        .frame(width: 9, height: 9)
                        .offset(x: geometry.size.width * thresholdPosition - 4.5)
                }
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
        .accessibilityLabel("Relative voice meter")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}
