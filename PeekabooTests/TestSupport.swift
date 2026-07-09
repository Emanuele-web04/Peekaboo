import Foundation
import SwiftData
@testable import Peekaboo

@MainActor
func makeTestStore(
    now: @escaping () -> Date = Date.init,
    persist: @escaping (ModelContext) throws -> Void = { try $0.save() }
) throws -> TaskStore {
    let container = try PersistenceController.makeContainer(inMemory: true)
    return TaskStore(container: container, now: now, persist: persist)
}

final class MutableNow {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}

@MainActor
final class PersistenceGate {
    struct Failure: Error {}

    var shouldFail = false

    func save(_ context: ModelContext) throws {
        if shouldFail { throw Failure() }
        try context.save()
    }
}
