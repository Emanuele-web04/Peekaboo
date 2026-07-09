import Foundation

struct MCPHTTPResult {
    let status: Int
    let reason: String
    let body: Data?

    static let accepted = MCPHTTPResult(status: 202, reason: "Accepted", body: nil)
}

/// Implements the server side of the MCP Streamable HTTP transport: a single
/// JSON-RPC message per POST, answered with a plain JSON response. The server
/// is stateless, so no session ids or SSE streams are needed.
@MainActor
final class MCPRequestHandler {
    static let supportedProtocolVersions = ["2025-06-18", "2025-03-26"]

    private let tools: AgentTaskTools
    private let serverVersion: String

    init(tools: AgentTaskTools, serverVersion: String = MCPRequestHandler.appVersion) {
        self.tools = tools
        self.serverVersion = serverVersion
    }

    func handle(body: Data) -> MCPHTTPResult {
        guard let json = try? JSONSerialization.jsonObject(with: body) else {
            return errorResponse(id: NSNull(), code: -32700, message: "Parse error")
        }
        guard let message = json as? [String: Any] else {
            return errorResponse(id: NSNull(), code: -32600, message: "Batch requests are not supported")
        }
        guard let method = message["method"] as? String else {
            // A response or malformed message from the client; nothing to answer.
            return .accepted
        }
        guard let id = requestID(of: message) else {
            // Notifications (initialized, cancelled, …) expect no body.
            return .accepted
        }

        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            return resultResponse(id: id, result: initializeResult(params: params))
        case "ping":
            return resultResponse(id: id, result: [:])
        case "tools/list":
            return resultResponse(id: id, result: ["tools": AgentTaskTools.definitions])
        case "tools/call":
            return callTool(id: id, params: params)
        default:
            return errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func initializeResult(params: [String: Any]) -> [String: Any] {
        let requested = params["protocolVersion"] as? String
        let version = Self.supportedProtocolVersions.contains(requested ?? "")
            ? requested!
            : Self.supportedProtocolVersions[0]
        return [
            "protocolVersion": version,
            "capabilities": ["tools": [:] as [String: Any]],
            "serverInfo": [
                "name": "peekaboo",
                "title": "Peekaboo Tasks",
                "version": serverVersion
            ],
            "instructions": "Peekaboo is the user's personal to-do list. Use list_tasks before updating so you reference current task ids. Keep titles short; use status backlog for ideas, inProgress for active work, and done to complete."
        ]
    }

    private func callTool(id: Any, params: [String: Any]) -> MCPHTTPResult {
        guard let name = params["name"] as? String else {
            return errorResponse(id: id, code: -32602, message: "Missing tool name")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        do {
            let text = try tools.call(name: name, arguments: arguments)
            return toolResponse(id: id, text: text, isError: false)
        } catch let error as AgentToolError {
            if case .unknownTool = error {
                return errorResponse(id: id, code: -32602, message: error.message)
            }
            return toolResponse(id: id, text: error.message, isError: true)
        } catch {
            return toolResponse(id: id, text: error.localizedDescription, isError: true)
        }
    }

    private func requestID(of message: [String: Any]) -> Any? {
        guard let id = message["id"], !(id is NSNull) else { return nil }
        return id
    }

    private func toolResponse(id: Any, text: String, isError: Bool) -> MCPHTTPResult {
        resultResponse(id: id, result: [
            "content": [["type": "text", "text": text]],
            "isError": isError
        ])
    }

    private func resultResponse(id: Any, result: [String: Any]) -> MCPHTTPResult {
        encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func errorResponse(id: Any, code: Int, message: String) -> MCPHTTPResult {
        encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    private func encode(_ payload: [String: Any]) -> MCPHTTPResult {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            let fallback = Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#.utf8)
            return MCPHTTPResult(status: 200, reason: "OK", body: fallback)
        }
        return MCPHTTPResult(status: 200, reason: "OK", body: data)
    }

    nonisolated private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
