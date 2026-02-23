import Foundation

actor WebSocketClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var continuation: AsyncStream<VehicleSummary>.Continuation?
    private var isConnected = false
    private var joinRef = 0
    private var msgRef = 0
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10

    private let serverURL: String
    private let jwt: String
    private let carId: Int

    init(serverURL: String, jwt: String, carId: Int) {
        self.serverURL = serverURL
        self.jwt = jwt
        self.carId = carId
    }

    func connect() -> AsyncStream<VehicleSummary> {
        let stream = AsyncStream<VehicleSummary> { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable _ in
                Task { await self.disconnect() }
            }
        }

        Task { await doConnect() }

        return stream
    }

    func disconnect() {
        isConnected = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        continuation?.finish()
        continuation = nil
    }

    private func doConnect() {
        let wsScheme = serverURL.hasPrefix("https") ? "wss" : "ws"
        let host = serverURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let url = URL(string: "\(wsScheme)://\(host)/api/v1/ws/websocket?token=\(jwt)&vsn=2.0.0") else {
            return
        }

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        reconnectAttempts = 0

        // Join the vehicle channel
        joinChannel()

        // Start heartbeat
        startHeartbeat()

        // Start receiving messages
        startReceiving()
    }

    private func joinChannel() {
        joinRef += 1
        msgRef += 1

        let joinMessage: [Any] = [
            "\(joinRef)",
            "\(msgRef)",
            "vehicle:\(carId)",
            "phx_join",
            [String: Any]()
        ]

        sendJSON(joinMessage)
    }

    private func startHeartbeat() {
        heartbeatTask = Task {
            while !Task.isCancelled && isConnected {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                guard !Task.isCancelled && isConnected else { break }

                msgRef += 1
                let heartbeat: [Any] = [
                    NSNull(),
                    "\(msgRef)",
                    "phoenix",
                    "heartbeat",
                    [String: Any]()
                ]
                sendJSON(heartbeat)
            }
        }
    }

    private func startReceiving() {
        receiveTask = Task {
            while !Task.isCancelled && isConnected {
                do {
                    guard let task = webSocketTask else { break }
                    let message = try await task.receive()

                    switch message {
                    case .string(let text):
                        handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled {
                        isConnected = false
                        attemptReconnect()
                    }
                    break
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count >= 5 else {
            return
        }

        let event = json[3] as? String ?? ""
        let payload = json[4]

        if event == "summary",
           let payloadData = try? JSONSerialization.data(withJSONObject: payload),
           let summary = try? {
               let decoder = JSONDecoder()
               decoder.keyDecodingStrategy = .convertFromSnakeCase
               return try decoder.decode(VehicleSummary.self, from: payloadData)
           }() {
            continuation?.yield(summary)
        }
    }

    private func sendJSON(_ message: [Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        webSocketTask?.send(.string(text)) { _ in }
    }

    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            continuation?.finish()
            return
        }

        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 60.0)

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            doConnect()
        }
    }
}
