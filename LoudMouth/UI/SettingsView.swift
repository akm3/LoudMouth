import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Privacy guarantee") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        PrivacyBadge(symbol: "memorychip", title: "Memory only")
                        PrivacyBadge(symbol: "network.slash", title: "No network")
                        PrivacyBadge(symbol: "waveform.slash", title: "No recordings")
                    }

                    Text("Live microphone samples are measured in memory and immediately discarded. LoudMouth never stores or transcribes audio; only a numeric calibration level and your preferences are saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 3)
            }

            Section("Voice reminders") {
                LabeledContent {
                    HStack(spacing: 10) {
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
                        .frame(width: 190)
                        Text(settings.sensitivityLabel)
                            .frame(width: 45, alignment: .trailing)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sensitivity")
                        Text("Move right to reach yellow and red sooner")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

            }

            Section("Energy") {
                Toggle(
                    "Monitor only during headphone calls",
                    isOn: $settings.monitorOnlyDuringHeadphoneCalls
                )

                Text("Stops microphone capture while no headphone call is active. Detection uses only local audio-device and activity flags — never call audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledContent("Current state", value: model.automaticMonitoringStatus)
                    .foregroundStyle(.secondary)
            }

            Section("Microphone") {
                Toggle("Prefer the Mac’s built-in microphone", isOn: $settings.preferBuiltInMicrophone)
                LabeledContent("Currently using", value: model.inputDeviceName)
                    .foregroundStyle(.secondary)
            }

            Section("Calibration") {
                LabeledContent("Natural voice level") {
                    Text(settings.baselineDecibelsFS == nil ? "Not calibrated" : "Calibrated")
                        .foregroundStyle(settings.baselineDecibelsFS == nil ? Color.secondary : Color.green)
                }
                Button("Reset Voice Calibration", role: .destructive) {
                    model.resetCalibration()
                }
                .disabled(settings.baselineDecibelsFS == nil)
            }

            Section {
                HStack {
                    Label("Zero collected data · Zero tracking", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit LoudMouth") { NSApplication.shared.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 680)
        .navigationTitle("LoudMouth Settings")
        .onChange(of: settings.preferBuiltInMicrophone) {
            model.refreshInputDevice()
        }
    }
}

private struct PrivacyBadge: View {
    let symbol: String
    let title: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.green.opacity(0.09), in: Capsule())
    }
}
