import SwiftData
import XCTest
@testable import PeekabooMobile

final class TaskStoreMobileTests: XCTestCase {
    @MainActor
    func testMobileUsesSharedTaskSemanticsWithoutCloudKitInTests() throws {
        let configuration = PersistenceController.makeConfiguration(inMemory: true)
        XCTAssertNil(configuration.cloudKitContainerIdentifier)

        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = TaskStore(container: container)
        let task = try XCTUnwrap(
            store.create(title: "  From   iPhone ", priority: .high, status: .backlog)
        )

        XCTAssertEqual(task.title, "From iPhone")
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.status, .backlog)

        XCTAssertTrue(store.update(task, status: .todo))
        XCTAssertEqual(task.status, .todo)
    }
}
