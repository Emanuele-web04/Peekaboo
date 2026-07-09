import SwiftUI

struct MobileAppRoot: View {
    @ObservedObject var appModel: MobileAppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let store = appModel.store {
                MobileTaskListScreen(
                    store: store,
                    iCloudAvailability: appModel.iCloudAvailability,
                    refresh: appModel.refresh
                )
            } else {
                startupFailure
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, appModel.store != nil else { return }
            Task { await appModel.refresh() }
        }
    }

    private var startupFailure: some View {
        ContentUnavailableView {
            Label("Tasks unavailable", systemImage: "exclamationmark.icloud")
        } description: {
            Text(appModel.startupError ?? "Peekaboo couldn't open its task store.")
        } actions: {
            Button("Try Again", action: appModel.loadStore)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
