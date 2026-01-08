import Foundation
import Dispatch
import Network

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
}

enum HTTPBody: Sendable {
    case empty
    case data(Data)
    case file(URL, byteCount: Int)
}

struct HTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    static func html(_ string: String, statusCode: Int = 200, extraHeaders: [String: String] = [:]) -> HTTPResponse {
        var headers = extraHeaders
        headers["Content-Type"] = "text/html; charset=utf-8"
        return HTTPResponse(statusCode: statusCode, headers: headers, body: Data(string.utf8))
    }

    static func json(_ data: Data, statusCode: Int = 200, extraHeaders: [String: String] = [:]) -> HTTPResponse {
        var headers = extraHeaders
        headers["Content-Type"] = "application/json; charset=utf-8"
        return HTTPResponse(statusCode: statusCode, headers: headers, body: data)
    }

    static func text(_ string: String, statusCode: Int, extraHeaders: [String: String] = [:]) -> HTTPResponse {
        var headers = extraHeaders
        headers["Content-Type"] = "text/plain; charset=utf-8"
        return HTTPResponse(statusCode: statusCode, headers: headers, body: Data(string.utf8))
    }

    static func redirect(to location: String, statusCode: Int = 302) -> HTTPResponse {
        HTTPResponse(statusCode: statusCode, headers: ["Location": location], body: Data())
    }
}

final class HTTPServer {
    typealias Handler = @Sendable (HTTPRequest, HTTPBody) async -> HTTPResponse

    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let handler: Handler
    private var listener: NWListener?

    init(host: String, port: UInt16, handler: @escaping Handler) throws {
        self.host = NWEndpoint.Host(host)
        guard let port = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "HTTPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid port"])
        }
        self.port = port
        self.handler = handler
    }

    func start() async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: port)
        let resumeQueue = DispatchQueue(label: "frtmtools.httpserver.start")
        var didResume = false

        listener.newConnectionHandler = { [handler] connection in
            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
            Task {
                await Self.handleConnection(connection, handler: handler)
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                resumeQueue.sync {
                    switch state {
                    case .ready:
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume()
                    case .failed(let error):
                        guard !didResume else { return }
                        didResume = true
                        fputs("HTTP server failed: \(error)\n", stderr)
                        continuation.resume(throwing: error)
                    default:
                        break
                    }
                }
            }
            listener.start(queue: DispatchQueue.global(qos: .userInitiated))
        }

        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    var boundPort: UInt16? {
        guard let listener else { return nil }
        return listener.port?.rawValue
    }

    private static func handleConnection(_ connection: NWConnection, handler: @escaping Handler) async {
        do {
            let (request, headerBytes, remainingBodyBytes) = try await receiveRequestHeader(connection)
            let contentLength = Int(request.headers["content-length"] ?? "") ?? 0

            let body: HTTPBody
            if contentLength == 0 {
                body = .empty
            } else {
                let shouldStreamToFile = request.method == "POST" && request.path == "/api/runs"
                if shouldStreamToFile {
                    body = try await receiveBodyToTemporaryFile(
                        connection,
                        alreadyReceived: remainingBodyBytes,
                        totalLength: contentLength
                    )
                } else {
                    let data = try await receiveBodyData(
                        connection,
                        alreadyReceived: remainingBodyBytes,
                        totalLength: contentLength
                    )
                    body = .data(data)
                }
            }

            _ = headerBytes
            let response = await handler(request, body)
            await sendResponse(connection, response: response)
        } catch {
            let response = HTTPResponse.text("Bad Request", statusCode: 400)
            await sendResponse(connection, response: response)
        }
        connection.cancel()
    }

    private static func receiveRequestHeader(_ connection: NWConnection) async throws -> (HTTPRequest, Data, Data) {
        var buffer = Data()
        while true {
            let chunk = try await receiveChunk(connection)
            if chunk.isEmpty { throw NSError(domain: "HTTPServer", code: 2) }
            buffer.append(chunk)
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: 0..<range.lowerBound)
                let remaining = buffer.subdata(in: range.upperBound..<buffer.count)
                let headerString = String(decoding: headerData, as: UTF8.self)
                let request = try parseRequest(headerString)
                return (request, headerData, remaining)
            }
            if buffer.count > 1024 * 1024 {
                throw NSError(domain: "HTTPServer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Headers too large"])
            }
        }
    }

    private static func receiveBodyData(_ connection: NWConnection, alreadyReceived: Data, totalLength: Int) async throws -> Data {
        var body = Data()
        body.reserveCapacity(totalLength)
        body.append(alreadyReceived)
        while body.count < totalLength {
            let chunk = try await receiveChunk(connection)
            if chunk.isEmpty { break }
            body.append(chunk)
        }
        if body.count > totalLength {
            body = body.prefix(totalLength)
        }
        return body
    }

    private static func receiveBodyToTemporaryFile(_ connection: NWConnection, alreadyReceived: Data, totalLength: Int) async throws -> HTTPBody {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("frtmtools-upload-\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempURL)
        defer { try? fileHandle.close() }

        var written = 0
        if !alreadyReceived.isEmpty {
            let initial = alreadyReceived.prefix(totalLength)
            fileHandle.write(Data(initial))
            written += initial.count
        }

        while written < totalLength {
            let chunk = try await receiveChunk(connection)
            if chunk.isEmpty { break }
            let remaining = totalLength - written
            let slice = chunk.prefix(remaining)
            fileHandle.write(Data(slice))
            written += slice.count
        }

        return .file(tempURL, byteCount: written)
    }

    private static func receiveChunk(_ connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if isComplete, data == nil {
                    continuation.resume(returning: Data())
                    return
                }
                continuation.resume(returning: data ?? Data())
            }
        }
    }

    private static func parseRequest(_ headerString: String) throws -> HTTPRequest {
        let lines = headerString.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first else {
            throw NSError(domain: "HTTPServer", code: 4)
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            throw NSError(domain: "HTTPServer", code: 5)
        }
        let method = String(parts[0]).uppercased()
        let rawTarget = String(parts[1])

        let components = URLComponents(string: rawTarget.hasPrefix("/") ? "http://localhost\(rawTarget)" : rawTarget)
        let path = components?.path ?? rawTarget
        var query: [String: String] = [:]
        components?.queryItems?.forEach { item in
            if let value = item.value {
                query[item.name] = value
            }
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            let pair = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            headers[pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
                pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return HTTPRequest(method: method, path: path, query: query, headers: headers)
    }

    private static func sendResponse(_ connection: NWConnection, response: HTTPResponse) async {
        var headers = response.headers
        headers["Content-Length"] = "\(response.body.count)"
        headers["Connection"] = "close"

        let statusLine = "HTTP/1.1 \(response.statusCode) \(reasonPhrase(for: response.statusCode))\r\n"
        let headerLines = headers
            .map { "\($0): \($1)\r\n" }
            .joined()
        let head = Data((statusLine + headerLines + "\r\n").utf8)
        let payload = head + response.body

        _ = await withCheckedContinuation { continuation in
            connection.send(content: payload, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }

    private static func reasonPhrase(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 202: return "Accepted"
        case 302: return "Found"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 500: return "Internal Server Error"
        default: return "OK"
        }
    }
}
