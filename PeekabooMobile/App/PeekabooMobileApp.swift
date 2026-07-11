import SwiftUI
import UIKit

final class MobileAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // CloudKit imports are triggered by silent APNs pushes while the app
        // is suspended. Register explicitly so delivery does not depend on a
        // previous foreground launch path.
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NSLog("Remote notification registration failed: %@", error.localizedDescription)
    }
}

@main
struct PeekabooMobileApp: App {
    @UIApplicationDelegateAdaptor(MobileAppDelegate.self) private var appDelegate
    @StateObject private var appModel = MobileAppModel()

    var body: some Scene {
        WindowGroup {
            MobileAppRoot(appModel: appModel)
        }
    }
}
