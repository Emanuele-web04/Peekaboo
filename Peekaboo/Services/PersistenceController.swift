import Foundation
import SwiftData

enum PersistenceController {
    static let cloudKitContainerIdentifier = "iCloud.com.emanueledipietro.Peekaboo"

    static func makeConfiguration(
        inMemory: Bool = false,
        cloudSyncEnabled: Bool = true
    ) -> ModelConfiguration {
        let cloudDatabase: ModelConfiguration.CloudKitDatabase =
            inMemory || !cloudSyncEnabled
                ? .none
                : .private(cloudKitContainerIdentifier)

        return ModelConfiguration(
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudDatabase
        )
    }

    static func makeContainer(
        inMemory: Bool = false,
        cloudSyncEnabled: Bool = true
    ) throws -> ModelContainer {
        let configuration = makeConfiguration(
            inMemory: inMemory,
            cloudSyncEnabled: cloudSyncEnabled
        )
        if !inMemory && cloudSyncEnabled {
            try createPreCloudKitBackupIfNeeded(for: configuration)
        }
        return try ModelContainer(for: TaskItem.self, configurations: configuration)
    }

    /// Copies the unopened legacy SQLite store once before CloudKit first
    /// attaches to it. The app continues to use the original files.
    private static func createPreCloudKitBackupIfNeeded(
        for configuration: ModelConfiguration,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) throws {
        let marker = "didCreatePreCloudKitStoreBackupV1"
        guard !defaults.bool(forKey: marker) else { return }

        let storeURL = configuration.url
        guard fileManager.fileExists(atPath: storeURL.path) else {
            defaults.set(true, forKey: marker)
            return
        }

        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }

            let destination = URL(
                fileURLWithPath: storeURL.path + ".pre-cloudkit" + suffix
            )
            if !fileManager.fileExists(atPath: destination.path) {
                try fileManager.copyItem(at: source, to: destination)
            }
        }

        defaults.set(true, forKey: marker)
    }
}
