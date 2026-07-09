import SwiftUI

@main
struct PeekabooMobileApp: App {
    @StateObject private var appModel = MobileAppModel()

    var body: some Scene {
        WindowGroup {
            MobileAppRoot(appModel: appModel)
        }
    }
}
