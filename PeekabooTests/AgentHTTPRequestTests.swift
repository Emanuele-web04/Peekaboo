import XCTest
@testable import Peekaboo

final class AgentHTTPRequestTests: XCTestCase {
    func testParsesCompleteRequestWithBody() throws {
        let raw = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}"
        guard case let .request(request) = AgentHTTPRequest.parse(Data(raw.utf8)) else {
            return XCTFail("Expected a parsed request")
        }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/mcp")
        XCTAssertEqual(request.headers["content-type"], "application/json")
        XCTAssertEqual(request.body, Data("{}".utf8))
    }

    func testStripsQueryFromPath() throws {
        let raw = "GET /mcp?session=1 HTTP/1.1\r\n\r\n"
        guard case let .request(request) = AgentHTTPRequest.parse(Data(raw.utf8)) else {
            return XCTFail("Expected a parsed request")
        }
        XCTAssertEqual(request.path, "/mcp")
        XCTAssertTrue(request.body.isEmpty)
    }

    func testIncompleteHeadReturnsIncomplete() {
        guard case .incomplete = AgentHTTPRequest.parse(Data("POST /mcp HTTP/1.1\r\nContent".utf8)) else {
            return XCTFail("Expected incomplete")
        }
    }

    func testIncompleteBodyReturnsIncomplete() {
        let raw = "POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\n{}"
        guard case .incomplete = AgentHTTPRequest.parse(Data(raw.utf8)) else {
            return XCTFail("Expected incomplete")
        }
    }

    func testMalformedRequestLineReturnsInvalid() {
        guard case .invalid = AgentHTTPRequest.parse(Data("NOT A REQUEST\r\n\r\n".utf8)) else {
            return XCTFail("Expected invalid")
        }
    }

    func testNegativeContentLengthReturnsInvalid() {
        let raw = "POST /mcp HTTP/1.1\r\nContent-Length: -5\r\n\r\n"
        guard case .invalid = AgentHTTPRequest.parse(Data(raw.utf8)) else {
            return XCTFail("Expected invalid")
        }
    }

    func testTransferEncodingReturnsInvalid() {
        let raw = "POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n{}\r\n0\r\n\r\n"
        guard case .invalid = AgentHTTPRequest.parse(Data(raw.utf8)) else {
            return XCTFail("Expected invalid")
        }
    }

    func testConflictingContentLengthsReturnInvalid() {
        let raw = "POST /mcp HTTP/1.1\r\nContent-Length: 2\r\nContent-Length: 4\r\n\r\n{}"
        guard case .invalid = AgentHTTPRequest.parse(Data(raw.utf8)) else {
            return XCTFail("Expected invalid")
        }
    }

    /// Feeds the request one byte at a time, resuming each parse from the
    /// offset reported by the previous one, exactly like AgentServer.receive.
    /// Splitting on every byte also covers a head terminator that straddles
    /// two chunks.
    func testIncrementalParsingAcrossSingleByteChunksFindsRequest() throws {
        let raw = "POST /mcp HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 7\r\n\r\n{\"a\":1}"
        let bytes = Array(raw.utf8)

        var buffer = Data()
        var searchedBytes = 0
        var parsedRequest: AgentHTTPRequest?

        for (index, byte) in bytes.enumerated() {
            buffer.append(byte)
            switch AgentHTTPRequest.parse(buffer, searchedBytes: searchedBytes) {
            case let .request(request):
                XCTAssertEqual(index, bytes.count - 1, "Parsed before all bytes arrived")
                parsedRequest = request
            case let .incomplete(searched):
                XCTAssertLessThan(index, bytes.count - 1, "Last byte should complete the request")
                XCTAssertLessThanOrEqual(searched, buffer.count)
                searchedBytes = searched
            case .invalid:
                return XCTFail("Unexpected invalid at byte \(index)")
            }
        }

        let request = try XCTUnwrap(parsedRequest)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/mcp")
        XCTAssertEqual(request.headers["content-length"], "7")
        XCTAssertEqual(request.body, Data("{\"a\":1}".utf8))
    }

    func testIncrementalParsingWaitsForBodyAfterHeadIsFound() throws {
        let head = "POST /mcp HTTP/1.1\r\nContent-Length: 2\r\n\r\n"
        var buffer = Data(head.utf8)

        guard case let .incomplete(searched) = AgentHTTPRequest.parse(buffer) else {
            return XCTFail("Expected incomplete while the body is missing")
        }

        buffer.append(Data("{}".utf8))
        guard case let .request(request) = AgentHTTPRequest.parse(buffer, searchedBytes: searched) else {
            return XCTFail("Expected a parsed request once the body arrived")
        }
        XCTAssertEqual(request.body, Data("{}".utf8))
    }

    func testAgentRequestSecurityRequiresLoopbackHostAndBearerToken() {
        let token = "test-secret"
        XCTAssertTrue(AgentRequestSecurity.isAuthorized(
            headers: [
                "host": "127.0.0.1:7335",
                "authorization": "Bearer \(token)"
            ],
            bearerToken: token
        ))
        XCTAssertFalse(AgentRequestSecurity.isAuthorized(
            headers: ["host": "127.0.0.1:7335"],
            bearerToken: token
        ))
        XCTAssertFalse(AgentRequestSecurity.isAuthorized(
            headers: [
                "host": "evil.example:7335",
                "authorization": "Bearer \(token)"
            ],
            bearerToken: token
        ))
        XCTAssertFalse(AgentRequestSecurity.isAuthorized(
            headers: [
                "host": "127.0.0.1:7335",
                "authorization": "Bearer wrong"
            ],
            bearerToken: token
        ))
    }
}
