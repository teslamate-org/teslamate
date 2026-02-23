import Foundation

@Observable
class OverviewViewModel {
    var summary: VehicleSummary?
    var isLoading = false
    var error: String?

    private var webSocketClient: WebSocketClient?
    private var streamTask: Task<Void, Never>?

    func startListening(carId: Int) async {
        let auth = AuthService.shared
        guard let jwt = await auth.jwt else { return }
        let serverURL = await auth.serverURL

        webSocketClient = WebSocketClient(serverURL: serverURL, jwt: jwt, carId: carId)

        guard let client = webSocketClient else { return }

        let stream = await client.connect()

        streamTask = Task {
            for await update in stream {
                await MainActor.run {
                    self.summary = update
                    self.error = nil
                }
            }
        }
    }

    func stopListening() async {
        streamTask?.cancel()
        streamTask = nil
        await webSocketClient?.disconnect()
        webSocketClient = nil
    }

    func refresh(carId: Int) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let newSummary = try await APIClient.shared.getCarSummary(carId: carId)
            await MainActor.run {
                self.summary = newSummary
                self.error = nil
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
}
