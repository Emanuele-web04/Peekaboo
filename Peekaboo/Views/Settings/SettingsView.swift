import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var loginItemService: LoginItemService
    @ObservedObject var agentServer: AgentServer
    @ObservedObject var store: TaskStore
    let agentAccessToken: String

    var body: some View {
        // Scrolls when the window is shorter than the content (small screens,
        // extra sections like sync errors); the window caps its own height.
        ScrollView {
            content
        }
        .frame(width: 520)
        .onAppear {
            loginItemService.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItemService.refresh()
        }
    }

    private var content: some View {
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

            cloudSyncSection

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $settings.isAgentAccessEnabled) {
                    Label("Agent access", systemImage: "sparkles")
                        .font(.headline)
                }

                Text("Allow local AI agents to read, create, update and permanently delete tasks over MCP.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.isAgentAccessEnabled {
                    agentServerStatus

                    Text(verbatim: "http://127.0.0.1:\(settings.agentServerPort)/mcp")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)

                    Text("Authorization: Bearer \(agentAccessToken)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help("Required authorization header for local MCP clients")
                }
            }

            if let message = settings.cloudSyncStartupErrorMessage {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Label("iCloud sync unavailable", systemImage: "exclamationmark.icloud.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("Peekaboo is using its local task store for this launch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                        .help(message)
                }
            }

            aboutFooter
        }
        .padding(28)
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

    private var cloudSyncSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.cloudSyncStatus.title, systemImage: store.cloudSyncStatus.symbolName)
                .font(.headline)
                .foregroundStyle(
                    store.cloudSyncStatus.lastErrorMessage == nil ? Color.primary : Color.orange
                )

            if let lastSuccess = store.cloudSyncStatus.lastSuccessfulActivityAt {
                Text("Last successful iCloud activity \(lastSuccess.formatted(date: .abbreviated, time: .standard)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Peekaboo is waiting for its first completed iCloud import or export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = store.cloudSyncStatus.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .help(error)
            }
        }
    }

    @ViewBuilder
    private var agentServerStatus: some View {
        switch agentServer.state {
        case .stopped:
            Label("Server stopped", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .starting:
            Label("Starting local server…", systemImage: "circle.dotted")
                .foregroundStyle(.secondary)
        case .running:
            Label("Listening on this Mac only", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Could not start the server", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry") { agentServer.start() }
                    .buttonStyle(.link)
            }
        }
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
