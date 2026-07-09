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
}
