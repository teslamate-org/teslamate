import Foundation
import Security

actor AuthService {
    static let shared = AuthService()

    private let serverURLKey = "teslamate_server_url"
    private let keychainService = "com.drewpost.TeslaMate"
    private let keychainJWTKey = "api_jwt"
    private let keychainTokenKey = "api_token"

    var serverURL: String {
        get { UserDefaults.standard.string(forKey: serverURLKey) ?? "" }
    }

    var isAuthenticated: Bool {
        get { loadFromKeychain(key: keychainJWTKey) != nil }
    }

    var jwt: String? {
        loadFromKeychain(key: keychainJWTKey)
    }

    var apiToken: String? {
        loadFromKeychain(key: keychainTokenKey)
    }

    func saveServerURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: serverURLKey)
    }

    func saveAPIToken(_ token: String) {
        saveToKeychain(key: keychainTokenKey, value: token)
    }

    func login() async throws -> AuthResponse {
        guard let token = apiToken else {
            throw APIError.notAuthenticated
        }

        let url = serverURL
        guard !url.isEmpty else {
            throw APIError.invalidURL
        }

        guard let requestURL = Endpoint.login.url(baseURL: url) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AuthRequest(token: token))

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw APIError.serverError(errorResponse.error)
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let authResponse = try decoder.decode(AuthResponse.self, from: data)

        saveToKeychain(key: keychainJWTKey, value: authResponse.jwt)

        return authResponse
    }

    func logout() {
        deleteFromKeychain(key: keychainJWTKey)
        deleteFromKeychain(key: keychainTokenKey)
        UserDefaults.standard.removeObject(forKey: serverURLKey)
    }

    func testConnection() async throws -> HealthResponse {
        let url = serverURL
        guard !url.isEmpty else {
            throw APIError.invalidURL
        }

        guard let requestURL = Endpoint.health.url(baseURL: url) else {
            throw APIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: requestURL))

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(HealthResponse.self, from: data)
    }

    // MARK: - Keychain Helpers

    private func saveToKeychain(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
