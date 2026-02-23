import Foundation

struct AuthResponse: Codable {
    let jwt: String
    let expiresAt: Int
}

struct AuthRequest: Codable {
    let token: String
}

struct APIErrorResponse: Codable {
    let error: String
}

struct PaginatedResponse<T: Codable>: Codable {
    let data: [T]
    let page: Int?
    let perPage: Int?
    let total: Int?
}

struct DataResponse<T: Codable>: Codable {
    let data: T
}

struct HealthResponse: Codable {
    let status: String
    let version: String
}
