import SwiftData

enum PersistenceController {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: TaskItem.self, configurations: configuration)
    }
}
