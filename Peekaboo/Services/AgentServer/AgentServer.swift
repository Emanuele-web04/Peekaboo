import Combine
import Foundation
import Network
import os

/// Loopback-only HTTP server that exposes the MCP endpoint at /mcp so local
/// AI agents (Claude Code, Codex, Synara, …) can read and update tasks.
@MainActor
final class AgentServer: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    static let defaultPort: UInt16 = 7335
    nonisolated private static let maxRequestBytes = 1_048_576

    @Published private(set) var state: State = .stopped

    private let port: UInt16
    private let handler: MCPRequestHandler
    private let queue = DispatchQueue(label: "com.emanueledipietro.Peekaboo.AgentServer")
    private let logger = Logger(subsystem: "com.emanueledipietro.Peekaboo", category: "AgentServer")
    private var listener: NWListener?

    init(port: UInt16, handler: MCPRequestHandler) {
        self.port = port
        self.handler = handler
    }

    func start() {
        guard listener == nil else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            logger.error("Invalid agent server port \(self.port)")
            state = .failed("Invalid port \(port).")
            return
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: endpointPort)

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            logger.error("Unable to create agent server listener: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
            return
        }

        state = .starting
        listener.stateUpdateHandler = { [weak self, weak listener, logger, port] state in
            switch state {
            case .ready:
                logger.info("Agent MCP server listening on http://127.0.0.1:\(port)/mcp")
                Task { @MainActor in
                    guard let self, let listener, self.listener === listener else { return }
                    self.state = .running
                }
            case let .failed(error):
                logger.error("Agent MCP server failed: \(error.localizedDescription)")
                Task { @MainActor in
                    guard let self, let listener, self.listener === listener else { return }
                    listener.cancel()
                    self.listener = nil
                    self.state = .failed(error.localizedDescription)
                }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .global())
            self?.receive(on: connection, buffer: Data())
        }

        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        state = .stopped
    }

    nonisolated private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            guard buffer.count <= Self.maxRequestBytes else {
                self.send(status: 413, reason: "Content Too Large", body: nil, on: connection)
                return
            }
            switch AgentHTTPRequest.parse(buffer) {
            case let .request(request):
                self.route(request, on: connection)
            case .invalid:
                self.send(status: 400, reason: "Bad Request", body: nil, on: connection)
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    nonisolated private func route(_ request: AgentHTTPRequest, on connection: NWConnection) {
        // Native agents never send an Origin header; a browser reaching this
        // endpoint through DNS rebinding would, so refuse any that appears.
        guard request.headers["origin"] == nil else {
            send(status: 403, reason: "Forbidden", body: nil, on: connection)
            return
        }
        guard request.path == "/mcp" else {
            send(status: 404, reason: "Not Found", body: nil, on: connection)
            return
        }
        guard request.method == "POST" else {
            send(status: 405, reason: "Method Not Allowed", body: nil, on: connection, extraHeaders: "Allow: POST\r\n")
            return
        }
        Task { @MainActor [weak self] in
            guard let self, self.listener != nil else {
                connection.cancel()
                return
            }
            let result = self.handler.handle(
                body: request.body,
                protocolVersion: request.headers["mcp-protocol-version"]
            )
            self.send(status: result.status, reason: result.reason, body: result.body, on: connection)
        }
    }

    nonisolated private func send(
        status: Int,
        reason: String,
        body: Data?,
        on connection: NWConnection,
        extraHeaders: String = ""
    ) {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Connection: close\r\n"
        head += extraHeaders
        if let body {
            head += "Content-Type: application/json\r\n"
            head += "Content-Length: \(body.count)\r\n"
        } else {
            head += "Content-Length: 0\r\n"
        }
        head += "\r\n"

        var response = Data(head.utf8)
        if let body {
            response.append(body)
        }
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
