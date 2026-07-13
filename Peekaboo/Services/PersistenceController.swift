import Foundation
import CoreData
import SwiftData

enum PeekabooCloudKitEnvironment: String {
    case development = "Development"
    case production = "Production"
}

enum PersistenceController {
    static let cloudKitContainerIdentifier = "iCloud.com.emanueledipietro.Peekaboo"
    private static let cloudKitEnvironmentInfoKey = "PeekabooCloudKitEnvironment"

    #if DEBUG
    /// Kept alive for the rest of the process because Core Data may finish
    /// CloudKit bookkeeping after `initializeCloudKitSchema` returns.
    @MainActor private static var retainedSchemaContainers: [NSPersistentCloudKitContainer] = []
    #endif

    static func makeConfiguration(
        inMemory: Bool = false,
        cloudSyncEnabled: Bool = true,
        environment: PeekabooCloudKitEnvironment? = nil
    ) -> ModelConfiguration {
        let cloudDatabase: ModelConfiguration.CloudKitDatabase =
            inMemory || !cloudSyncEnabled
                ? .none
                : .private(cloudKitContainerIdentifier)

        let defaultConfiguration = ModelConfiguration(
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudDatabase
        )
        let resolvedEnvironment = environment ?? currentCloudKitEnvironment
        guard !inMemory,
              resolvedEnvironment == .development else {
            return defaultConfiguration
        }

        // Never attach Development and Production CloudKit metadata to the
        // same SQLite store. Core Data persists scheduler activity identifiers
        // in the store; reusing it across environments can make a Sandbox push
        // execute against Production (or vice versa) and stall live sync.
        let developmentURL = defaultConfiguration.url
            .deletingLastPathComponent()
            .appendingPathComponent("development.store")
        return ModelConfiguration(
            "development",
            url: developmentURL,
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

    #if DEBUG
    /// Creates the Core Data record types in CloudKit's Development
    /// environment before SwiftData starts using the same store. Apple
    /// requires this schema bootstrap to happen only in development builds.
    @MainActor static func initializeCloudKitDevelopmentSchemaIfNeeded(
        defaults: UserDefaults = .standard
    ) throws {
        guard currentCloudKitEnvironment == .development else { return }
        let marker = "didInitializeCloudKitDevelopmentSchemaV1"
        guard !defaults.bool(forKey: marker) else { return }

        try autoreleasepool {
            let fileManager = FileManager.default
            let directory = fileManager.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent(
                "CloudKitSchemaBootstrap",
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let storeURL = directory.appendingPathComponent("schema.store")
            let description = NSPersistentStoreDescription(url: storeURL)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: cloudKitContainerIdentifier
            )
            description.shouldAddStoreAsynchronously = false

            guard let managedObjectModel = NSManagedObjectModel.makeManagedObjectModel(
                for: [TaskItem.self]
            ) else {
                throw CloudKitSchemaInitializationError.unableToCreateManagedObjectModel
            }

            let container = NSPersistentCloudKitContainer(
                name: "PeekabooCloudKitSchema",
                managedObjectModel: managedObjectModel
            )
            container.persistentStoreDescriptions = [description]

            var loadError: Error?
            container.loadPersistentStores { _, error in
                loadError = error
            }
            if let loadError { throw loadError }

            try container.initializeCloudKitSchema(options: [])
            retainedSchemaContainers.append(container)
        }

        defaults.set(true, forKey: marker)
    }
    #endif

    static var currentCloudKitEnvironment: PeekabooCloudKitEnvironment {
        if let rawValue = Bundle.main.object(
            forInfoDictionaryKey: cloudKitEnvironmentInfoKey
        ) as? String,
           let environment = PeekabooCloudKitEnvironment(rawValue: rawValue) {
            return environment
        }

        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }

    /// Copies the unopened legacy SQLite store once before CloudKit first
    /// attaches to it. The app continues to use the original files.
    private static func createPreCloudKitBackupIfNeeded(
        for configuration: ModelConfiguration,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) throws {
        let marker = "didCreatePreCloudKitStoreBackupV2.\(configuration.url.standardizedFileURL.path)"
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

#if DEBUG
private enum CloudKitSchemaInitializationError: LocalizedError {
    case unableToCreateManagedObjectModel

    var errorDescription: String? {
        "Unable to create the Core Data model required to initialize CloudKit."
    }
}
#endif
