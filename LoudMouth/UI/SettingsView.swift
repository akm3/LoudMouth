import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var launchAtLogin = LoginItemController()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LoudMouth Settings")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("A calmer way to stay aware of your volume.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Quit LoudMouth", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
            }

            SettingsCard("Startup & energy", symbol: "power") {
                Toggle("Launch LoudMouth at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .onAppear { launchAtLogin.refresh() }

                Toggle(
                    "Monitor only during headphone calls",
                    isOn: $settings.monitorOnlyDuringHeadphoneCalls
                )

                HStack {
                    Text("Current state")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(model.automaticMonitoringStatus)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                if let errorMessage = launchAtLogin.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsCard("Voice reminders", symbol: "waveform") {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sensitivity")
                        Text("Move right to reach yellow and red sooner")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 190, alignment: .leading)

                    VStack(spacing: 2) {
                        Slider(
                            value: Binding(
                                get: { settings.sensitivity },
                                set: { settings.sensitivity = $0 }
                            ),
                            in: 0...1
                        )
                        HStack {
                            Text("Less")
                            Spacer()
                            Text("More")
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    }

                    Text(settings.sensitivityLabel)
                        .font(.caption.weight(.semibold))
                        .frame(width: 48, alignment: .trailing)
                }
            }

            SettingsCard("Microphone & calibration", symbol: "mic") {
                Toggle("Prefer the Mac’s built-in microphone", isOn: $settings.preferBuiltInMicrophone)

                HStack {
                    Text("Currently using")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(model.inputDeviceName)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                Divider()

                HStack {
                    Label(
                        settings.baselineDecibelsFS == nil ? "Voice calibration needed" : "Voice calibrated",
                        systemImage: settings.baselineDecibelsFS == nil ? "exclamationmark.circle" : "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(settings.baselineDecibelsFS == nil ? Color.secondary : Color.green)

                    Spacer()

                    Button("Reset Calibration", role: .destructive) {
                        model.resetCalibration()
                    }
                    .controlSize(.small)
                    .disabled(settings.baselineDecibelsFS == nil)
                }
            }

            Spacer(minLength: 0)

            PrivacyGuarantee()
        }
        .padding(20)
        .frame(width: 560, height: 560, alignment: .top)
        .navigationTitle("LoudMouth Settings")
        .onChange(of: settings.preferBuiltInMicrophone) {
            model.refreshInputDevice()
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
            content
        }
        .padding(14)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PrivacyGuarantee: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PrivacyBadge(symbol: "memorychip", title: "Memory only")
                PrivacyBadge(symbol: "network.slash", title: "No network")
                PrivacyBadge(symbol: "waveform.slash", title: "No recordings")
                Spacer()
            }

            Text("Privacy guarantee: live microphone samples are measured in memory and immediately discarded. LoudMouth never stores or transcribes audio; only a numeric calibration level and your preferences are saved.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.green.opacity(0.065), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PrivacyBadge: View {
    let symbol: String
    let title: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.green.opacity(0.09), in: Capsule())
    }
}
