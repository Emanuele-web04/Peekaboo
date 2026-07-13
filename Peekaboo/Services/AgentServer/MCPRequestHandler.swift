import CoreFoundation
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
    static let supportedProtocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26"]

    private let tools: AgentTaskTools
    private let serverVersion: String

    init(tools: AgentTaskTools, serverVersion: String = MCPRequestHandler.appVersion) {
        self.tools = tools
        self.serverVersion = serverVersion
    }

    func handle(body: Data, protocolVersion: String? = nil) -> MCPHTTPResult {
        guard let json = try? JSONSerialization.jsonObject(with: body) else {
            return errorResponse(id: NSNull(), code: -32700, message: "Parse error")
        }
        guard let message = json as? [String: Any] else {
            return errorResponse(id: NSNull(), code: -32600, message: "Batch requests are not supported")
        }
        guard message["jsonrpc"] as? String == "2.0" else {
            return errorResponse(id: NSNull(), code: -32600, message: "Invalid JSON-RPC request")
        }

        let method = message["method"] as? String
        if method != "initialize" {
            let resolvedVersion = protocolVersion ?? "2025-03-26"
            guard Self.supportedProtocolVersions.contains(resolvedVersion) else {
                return badRequest("Unsupported MCP protocol version: \(resolvedVersion)")
            }
        }

        guard let method else {
            // Clients may send JSON-RPC responses over the same transport.
            if message["result"] != nil || message["error"] != nil {
                return .accepted
            }
            return errorResponse(id: NSNull(), code: -32600, message: "Invalid JSON-RPC request")
        }
        guard message.keys.contains("id") else {
            // Notifications (initialized, cancelled, …) expect no body.
            return .accepted
        }
        let id = message["id"] ?? NSNull()
        guard Self.isValidRequestID(id) else {
            return errorResponse(id: NSNull(), code: -32600, message: "Invalid request id")
        }
        let params: [String: Any]
        if let rawParams = message["params"] {
            guard let objectParams = rawParams as? [String: Any] else {
                return errorResponse(id: id, code: -32602, message: "Params must be an object")
            }
            params = objectParams
        } else {
            params = [:]
        }

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
            "instructions": "When the user says Peekaboo or asks to manage their Peekaboo task list, use these MCP tools directly. Do not open or control the Peekaboo GUI with Computer Use unless the user explicitly asks for UI interaction. Use list_tasks before updating so you reference current task ids. Keep titles short; use backlog for ideas, inProgress for active work, and done to complete."
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

    private func badRequest(_ message: String) -> MCPHTTPResult {
        let error = errorResponse(id: NSNull(), code: -32600, message: message)
        return MCPHTTPResult(status: 400, reason: "Bad Request", body: error.body)
    }

    private static func isValidRequestID(_ id: Any) -> Bool {
        if id is String || id is NSNull { return true }
        guard let number = id as? NSNumber else { return false }
        return CFGetTypeID(number) != CFBooleanGetTypeID()
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
