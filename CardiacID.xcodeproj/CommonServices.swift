import Foundation

/// API Error types for the application
enum APIError: LocalizedError {
    case networkError(Error)
    case authenticationError(String)
    case serverError(Int, String?)
    case decodingError(Error)
    case invalidURL
    case noData
    case timeout
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .authenticationError(let message):
            return "Authentication error: \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown")"
        case .decodingError(let error):
            return "Data parsing error: \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        case .timeout:
            return "Request timeout"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

/// Encryption service for securing data
class EncryptionService {
    static let shared = EncryptionService()
    private init() {}
    
    func encrypt(_ data: Data) throws -> Data {
        // Placeholder implementation
        return data
    }
    
    func decrypt(_ encryptedData: Data) throws -> Data {
        // Placeholder implementation
        return encryptedData
    }
    
    func encrypt(_ string: String) throws -> String {
        // Placeholder implementation
        return string
    }
    
    func decrypt(_ encryptedString: String) throws -> String {
        // Placeholder implementation
        return encryptedString
    }
}

/// Keychain service for secure storage
class KeychainService {
    static let shared = KeychainService()
    private init() {}
    
    func store(_ value: String, forKey key: String) throws {
        // Use SecureCredentialManager
        // This is a simplified wrapper
    }
    
    func retrieve(forKey key: String) throws -> String? {
        // Use SecureCredentialManager
        return nil
    }
    
    func delete(forKey key: String) throws {
        // Use SecureCredentialManager
    }
}

/// Microsoft Graph API client
class MicrosoftGraphClient {
    private let accessToken: String
    private let baseURL = "https://graph.microsoft.com/v1.0"
    
    init(accessToken: String) {
        self.accessToken = accessToken
    }
    
    func getUserProfile() async throws -> GraphUserProfile {
        let url = URL(string: "\(baseURL)/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GraphAPIError.requestFailed
        }
        
        return try JSONDecoder().decode(GraphUserProfile.self, from: data)
    }
}

struct GraphUserProfile: Codable {
    let id: String
    let displayName: String?
    let mail: String?
    let userPrincipalName: String
    let jobTitle: String?
    let department: String?
}

enum GraphAPIError: LocalizedError {
    case requestFailed
    case invalidResponse
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Microsoft Graph API request failed"
        case .invalidResponse:
            return "Invalid response from Microsoft Graph API"
        case .decodingError:
            return "Failed to decode Microsoft Graph API response"
        }
    }
}