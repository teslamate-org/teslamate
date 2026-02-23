import Foundation

@Observable
class SettingsViewModel {
    var serverURL: String = ""
    var apiToken: String = ""
    var isTestingConnection = false
    var isLoggingIn = false
    var connectionTestResult: String?
    var connectionTestSuccess = false
    var loginError: String?

    func loadSavedSettings() async {
        let auth = AuthService.shared
        serverURL = await auth.serverURL
        apiToken = await auth.apiToken ?? ""
    }

    func testConnection() async {
        guard !serverURL.isEmpty else {
            connectionTestResult = "Please enter a server URL"
            connectionTestSuccess = false
            return
        }

        isTestingConnection = true
        connectionTestResult = nil

        // Save URL first so the test can use it
        await AuthService.shared.saveServerURL(normalizedURL)

        do {
            let health = try await AuthService.shared.testConnection()
            await MainActor.run {
                self.connectionTestResult = "Connected! Server v\(health.version) - Status: \(health.status)"
                self.connectionTestSuccess = true
                self.isTestingConnection = false
            }
        } catch {
            await MainActor.run {
                self.connectionTestResult = "Connection failed: \(error.localizedDescription)"
                self.connectionTestSuccess = false
                self.isTestingConnection = false
            }
        }
    }

    func login(appState: AppState) async {
        guard !serverURL.isEmpty, !apiToken.isEmpty else {
            loginError = "Please enter server URL and API token"
            return
        }

        isLoggingIn = true
        loginError = nil

        await AuthService.shared.saveServerURL(normalizedURL)
        await AuthService.shared.saveAPIToken(apiToken)

        do {
            _ = try await AuthService.shared.login()
            await appState.checkAuth()
            await MainActor.run {
                self.isLoggingIn = false
            }
        } catch {
            await MainActor.run {
                self.loginError = error.localizedDescription
                self.isLoggingIn = false
            }
        }
    }

    private var normalizedURL: String {
        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix("/") {
            url.removeLast()
        }
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "http://" + url
        }
        return url
    }
}
