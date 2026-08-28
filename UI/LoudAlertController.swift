import AppKit
import SwiftUI

@MainActor
final class LoudAlertController {
    private var panel: NSPanel?

    func show() {
        let panel = panel ?? makePanel()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - 24,
            y: visible.maxY - size.height - 24
        ))
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func makePanel() -> NSPanel {
        let frame = NSRect(x: 0, y: 0, width: 254, height: 70)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: LoudAlertView())
        self.panel = panel
        return panel
    }
}

private struct LoudAlertView: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.red.opacity(0.16))
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.system(size: 19, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red)
                    .scaleEffect(pulse ? 1.06 : 0.94)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("You’re getting loud")
                    .font(.system(size: 14, weight: .semibold))
                Text("Ease back toward your natural voice")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 13)
        .frame(width: 254, height: 70)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.red.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
