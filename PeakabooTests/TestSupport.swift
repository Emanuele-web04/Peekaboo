import Foundation
import SwiftData
@testable import Peakaboo

@MainActor
func makeTestStore(now: @escaping () -> Date = Date.init) throws -> TaskStore {
    let container = try PersistenceController.makeContainer(inMemory: true)
    return TaskStore(container: container, now: now)
}

final class MutableNow {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}
