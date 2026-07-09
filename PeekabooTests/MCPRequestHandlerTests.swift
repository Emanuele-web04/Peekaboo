import XCTest
@testable import Peekaboo

@MainActor
final class MCPRequestHandlerTests: XCTestCase {
    private var store: TaskStore!
    private var handler: MCPRequestHandler!

    override func setUp() async throws {
        store = try makeTestStore()
        handler = MCPRequestHandler(tools: AgentTaskTools(store: store), serverVersion: "test")
    }

    override func tearDown() {
        store = nil
        handler = nil
    }

    func testInitializeAdvertisesToolsAndEchoesSupportedVersion() throws {
        let response = try send(method: "initialize", params: ["protocolVersion": "2025-03-26"])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        let capabilities = try XCTUnwrap(result["capabilities"] as? [String: Any])
        XCTAssertNotNil(capabilities["tools"])
        let serverInfo = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(serverInfo["name"] as? String, "peekaboo")
        let instructions = try XCTUnwrap(result["instructions"] as? String)
        XCTAssertTrue(instructions.contains("Do not open or control the Peekaboo GUI with Computer Use"))
    }

    func testInitializeFallsBackToLatestSupportedVersion() throws {
        let response = try send(method: "initialize", params: ["protocolVersion": "1999-01-01"])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-06-18")
    }

    func testNotificationReturnsAcceptedWithoutBody() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
        ])
        let result = handler.handle(body: body)
        XCTAssertEqual(result.status, 202)
        XCTAssertNil(result.body)
    }

    func testMalformedJSONReturnsParseError() throws {
        let result = handler.handle(body: Data("not json".utf8))
        let response = try decode(result)
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32700)
    }

    func testMissingJSONRPCVersionReturnsInvalidRequest() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "id": 1,
            "method": "ping"
        ])
        let response = try decode(handler.handle(body: body))
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
    }

    func testNullIDStillReceivesAResponse() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": NSNull(),
            "method": "ping"
        ])
        let response = try decode(handler.handle(body: body))
        XCTAssertTrue(response["id"] is NSNull)
        XCTAssertNotNil(response["result"])
    }

    func testBooleanIDReturnsInvalidRequest() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": true,
            "method": "ping"
        ])
        let response = try decode(handler.handle(body: body))
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
    }

    func testUnsupportedProtocolVersionReturnsHTTPBadRequest() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list"
        ])
        let result = handler.handle(body: body, protocolVersion: "1999-01-01")
        XCTAssertEqual(result.status, 400)
        XCTAssertEqual(result.reason, "Bad Request")
        XCTAssertNotNil(result.body)
    }

    func testNonObjectParamsReturnInvalidParams() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": []
        ])
        let response = try decode(handler.handle(body: body))
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32602)
    }

    func testUnknownMethodReturnsMethodNotFound() throws {
        let response = try send(method: "resources/list")
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32601)
    }

    func testToolsListReturnsAllTaskTools() throws {
        let response = try send(method: "tools/list")
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        XCTAssertEqual(
            tools.compactMap { $0["name"] as? String }.sorted(),
            ["create_task", "delete_task", "list_tasks", "update_task"]
        )
        let listTool = try XCTUnwrap(tools.first { $0["name"] as? String == "list_tasks" })
        let annotations = try XCTUnwrap(listTool["annotations"] as? [String: Any])
        XCTAssertEqual(annotations["readOnlyHint"] as? Bool, true)
        XCTAssertEqual(annotations["destructiveHint"] as? Bool, false)
    }

    func testCreateTaskInsertsTaskWithPriorityAndStatus() throws {
        let payload = try callTool("create_task", arguments: [
            "title": "  Ship   the MCP server ",
            "priority": "high",
            "status": "inProgress"
        ])
        let task = try XCTUnwrap(payload["task"] as? [String: Any])
        XCTAssertEqual(task["title"] as? String, "Ship the MCP server")
        XCTAssertEqual(task["status"] as? String, "inProgress")
        XCTAssertEqual(task["priority"] as? String, "high")
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks.first?.status, .inProgress)
    }

    func testCreateTaskWithoutTitleReturnsToolError() throws {
        let response = try send(method: "tools/call", params: [
            "name": "create_task",
            "arguments": ["title": "   "]
        ])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testListTasksFiltersByStatus() throws {
        let todo = try XCTUnwrap(store.create(title: "Todo item"))
        let backlogged = try XCTUnwrap(store.create(title: "Backlog item", status: .backlog))

        let payload = try callTool("list_tasks", arguments: ["status": "backlog"])
        let tasks = try XCTUnwrap(payload["tasks"] as? [[String: Any]])
        XCTAssertEqual(payload["count"] as? Int, 1)
        XCTAssertEqual(tasks.first?["id"] as? String, backlogged.id.uuidString)

        let allPayload = try callTool("list_tasks", arguments: [:])
        let allIDs = try XCTUnwrap(allPayload["tasks"] as? [[String: Any]]).compactMap { $0["id"] as? String }
        XCTAssertEqual(Set(allIDs), Set([todo.id.uuidString, backlogged.id.uuidString]))
    }

    func testUpdateTaskToDoneSetsCompletedAt() throws {
        let task = try XCTUnwrap(store.create(title: "Finish me"))

        let payload = try callTool("update_task", arguments: [
            "id": task.id.uuidString,
            "status": "done",
            "priority": "low",
            "title": "Finished"
        ])
        let updated = try XCTUnwrap(payload["task"] as? [String: Any])
        XCTAssertEqual(updated["status"] as? String, "done")
        XCTAssertEqual(updated["priority"] as? String, "low")
        XCTAssertEqual(updated["title"] as? String, "Finished")
        XCTAssertNotNil(updated["completedAt"])
        XCTAssertNotNil(task.completedAt)
    }

    func testUpdateTaskWithInvalidPriorityChangesNothing() throws {
        let task = try XCTUnwrap(store.create(title: "Keep me intact"))

        let response = try send(method: "tools/call", params: [
            "name": "update_task",
            "arguments": ["id": task.id.uuidString, "title": "Renamed", "priority": "urgent"]
        ])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertEqual(task.title, "Keep me intact")
    }

    func testUpdateTaskWithNonStringTitleChangesNothing() throws {
        let task = try XCTUnwrap(store.create(title: "Keep me intact"))

        let response = try send(method: "tools/call", params: [
            "name": "update_task",
            "arguments": ["id": task.id.uuidString, "title": 123, "status": "done"]
        ])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertEqual(task.title, "Keep me intact")
        XCTAssertEqual(task.status, .todo)
    }

    func testUpdateTaskWithUnknownIDReturnsToolError() throws {
        let response = try send(method: "tools/call", params: [
            "name": "update_task",
            "arguments": ["id": UUID().uuidString, "status": "done"]
        ])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
    }

    func testDeleteTaskRemovesTask() throws {
        let task = try XCTUnwrap(store.create(title: "Remove me"))
        let payload = try callTool("delete_task", arguments: ["id": task.id.uuidString])
        XCTAssertEqual(payload["deleted"] as? String, task.id.uuidString)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testUnknownToolReturnsInvalidParams() throws {
        let response = try send(method: "tools/call", params: ["name": "explode"])
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32602)
    }

    private func send(method: String, params: [String: Any] = [:], id: Int = 1) throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ])
        return try decode(handler.handle(body: body))
    }

    private func callTool(_ name: String, arguments: [String: Any]) throws -> [String: Any] {
        let response = try send(method: "tools/call", params: ["name": name, "arguments": arguments])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func decode(_ result: MCPHTTPResult) throws -> [String: Any] {
        XCTAssertEqual(result.status, 200)
        let body = try XCTUnwrap(result.body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}
