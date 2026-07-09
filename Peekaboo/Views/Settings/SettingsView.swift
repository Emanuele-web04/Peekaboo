import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var loginItemService: LoginItemService

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            HStack(alignment: .top, spacing: 28) {
                CornerPicker(selection: $settings.corner)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Hiding corner")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(settings.corner.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("The same corner works on every connected display.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("macOS Hot Corners may activate at the same time.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Hide delay", systemImage: "eye.slash")
                        .font(.headline)
                    Spacer()
                    Text(settings.hideDelay, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                    Text("sec")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.hideDelay, in: 0.1...2.0, step: 0.1)
                Text("Wait this long after the cursor leaves before Peekaboo hides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Reveal delay", systemImage: "timer")
                        .font(.headline)
                    Spacer()
                    Text(settings.revealDelay, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                    Text("sec")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.revealDelay, in: 0.2...2.0, step: 0.1)
                Text("Pause in the corner for this long before Peekaboo appears.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $settings.isTranslucent) {
                    Label("Translucency", systemImage: "circle.lefthalf.filled")
                        .font(.headline)
                }
                Text("Let the desktop shine through the panel background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: loginBinding) {
                    Label("Launch at login", systemImage: "power")
                        .font(.headline)
                }

                Text("Open Peekaboo automatically when you log in to this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if loginItemService.requiresApproval {
                    HStack {
                        Text("Approval is required in System Settings.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Open Login Items") { loginItemService.openSystemSettings() }
                            .buttonStyle(.link)
                    }
                }

                if let error = loginItemService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $settings.isAgentAccessEnabled) {
                    Label("Agent access", systemImage: "sparkles")
                        .font(.headline)
                }

                Text("Let AI agents on this Mac read and update your tasks over MCP.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.isAgentAccessEnabled {
                    Text(verbatim: "http://127.0.0.1:\(settings.agentServerPort)/mcp")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)

            aboutFooter
        }
        .padding(28)
        .frame(width: 520, height: 800)
        .onAppear {
            loginItemService.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItemService.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.primary)
                    .frame(width: 48, height: 48)
                Image(systemName: "eye.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Peekaboo")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("A quiet list, right around the corner.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { loginItemService.isEnabled },
            set: { loginItemService.setEnabled($0) }
        )
    }

    private var aboutFooter: some View {
        VStack(spacing: 7) {
            Text("Made by Emanuele Di Pietro")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Link(destination: URL(string: "https://github.com/Emanuele-web04/Peekaboo")!) {
                Label("Open source on GitHub", systemImage: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Open the Peekaboo repository")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }
}
