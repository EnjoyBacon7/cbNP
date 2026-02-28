import Foundation

actor WebSocketClient {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var connected = false

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        session = URLSession(configuration: config)
    }

    var isConnected: Bool {
        connected && task != nil
    }

    func connect(endpoint: URL) {
        task?.cancel(with: .normalClosure, reason: nil)
        let newTask = session.webSocketTask(with: endpoint)
        task = newTask
        connected = false
        newTask.resume()
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        connected = false
    }

    func send(jsonObject: [String: Any]) async throws {
        guard let task else {
            throw WebSocketError.notConnected
        }
        let data = try JSONSerialization.data(withJSONObject: jsonObject)
        guard let text = String(data: data, encoding: .utf8) else {
            throw WebSocketError.invalidPayload
        }
        do {
            try await task.send(.string(text))
            connected = true
        } catch {
            connected = false
            self.task = nil
            throw error
        }
    }
}

enum WebSocketError: LocalizedError {
    case notConnected
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .notConnected:  return "WebSocket is not connected."
        case .invalidPayload: return "Could not encode WebSocket payload."
        }
    }
}
