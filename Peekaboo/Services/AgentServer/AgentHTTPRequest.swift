import Foundation

struct AgentHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    enum ParseResult {
        case incomplete
        case invalid
        case request(AgentHTTPRequest)
    }

    /// Parses one HTTP/1.1 request from an accumulating buffer. Returns
    /// `.incomplete` until the head and the full Content-Length body arrived.
    static func parse(_ buffer: Data) -> ParseResult {
        guard let headRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return .incomplete
        }
        guard let head = String(data: buffer[buffer.startIndex..<headRange.lowerBound], encoding: .utf8) else {
            return .invalid
        }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().components(separatedBy: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else {
            return .invalid
        }
        let method = requestLine[0]
        let path = requestLine[1].components(separatedBy: "?")[0]

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            // Duplicate framing headers make the body length ambiguous.
            if name == "content-length", let existing = headers[name], existing != value {
                return .invalid
            }
            headers[name] = value
        }

        guard headers["transfer-encoding"] == nil else { return .invalid }

        var contentLength = 0
        if let rawLength = headers["content-length"] {
            guard let length = Int(rawLength), length >= 0 else { return .invalid }
            contentLength = length
        }

        let bodyStart = headRange.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= contentLength else {
            return .incomplete
        }
        let body = Data(buffer[bodyStart..<buffer.index(bodyStart, offsetBy: contentLength)])
        return .request(AgentHTTPRequest(method: method, path: path, headers: headers, body: body))
    }
}
