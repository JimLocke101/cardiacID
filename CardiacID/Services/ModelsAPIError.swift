import Foundation

/// API Error types for the application
public enum APIError: Error, LocalizedError, Codable {
    case networkError(String)
    case serverError(Int, String)
    case decodingError(String)
    case encodingError(String)
    case authenticationError(String)
    case authorizationError(String)
    case validationError([String])
    case notFound(String)
    case timeout(String)
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network Error: \(message)"
        case .serverError(let code, let message):
            return "Server Error (\(code)): \(message)"
        case .decodingError(let message):
            return "Data Parsing Error: \(message)"
        case .encodingError(let message):
            return "Data Encoding Error: \(message)"
        case .authenticationError(let message):
            return "Authentication Error: \(message)"
        case .authorizationError(let message):
            return "Authorization Error: \(message)"
        case .validationError(let errors):
            return "Validation Error: \(errors.joined(separator: ", "))"
        case .notFound(let message):
            return "Not Found: \(message)"
        case .timeout(let message):
            return "Timeout: \(message)"
        case .unknown(let message):
            return "Unknown Error: \(message)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .networkError:
            return "Unable to connect to the server. Please check your internet connection."
        case .serverError(let code, _):
            return code >= 500 ? "Server is experiencing issues. Please try again later." : "Request failed due to client error."
        case .decodingError, .encodingError:
            return "Data format error. Please try again or contact support."
        case .authenticationError:
            return "Please sign in again to continue."
        case .authorizationError:
            return "You don't have permission to perform this action."
        case .validationError:
            return "Please check your input and try again."
        case .notFound:
            return "The requested resource was not found."
        case .timeout:
            return "Request timed out. Please try again."
        case .unknown:
            return "An unexpected error occurred. Please try again."
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "Check your internet connection and try again."
        case .serverError(let code, _):
            return code >= 500 ? "Wait a moment and try again." : "Review your request and try again."
        case .decodingError, .encodingError:
            return "If the problem persists, please contact support."
        case .authenticationError:
            return "Sign in again to continue."
        case .authorizationError:
            return "Contact your administrator for access."
        case .validationError:
            return "Correct the highlighted fields and try again."
        case .notFound:
            return "Verify the resource exists and try again."
        case .timeout:
            return "Check your connection and try again."
        case .unknown:
            return "If the problem persists, please contact support."
        }
    }
    
    // MARK: - Codable Implementation
    
    enum CodingKeys: String, CodingKey {
        case type
        case message
        case code
        case errors
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "network":
            let message = try container.decode(String.self, forKey: .message)
            self = .networkError(message)
        case "server":
            let code = try container.decode(Int.self, forKey: .code)
            let message = try container.decode(String.self, forKey: .message)
            self = .serverError(code, message)
        case "decoding":
            let message = try container.decode(String.self, forKey: .message)
            self = .decodingError(message)
        case "encoding":
            let message = try container.decode(String.self, forKey: .message)
            self = .encodingError(message)
        case "authentication":
            let message = try container.decode(String.self, forKey: .message)
            self = .authenticationError(message)
        case "authorization":
            let message = try container.decode(String.self, forKey: .message)
            self = .authorizationError(message)
        case "validation":
            let errors = try container.decode([String].self, forKey: .errors)
            self = .validationError(errors)
        case "notFound":
            let message = try container.decode(String.self, forKey: .message)
            self = .notFound(message)
        case "timeout":
            let message = try container.decode(String.self, forKey: .message)
            self = .timeout(message)
        default:
            let message = try container.decode(String.self, forKey: .message)
            self = .unknown(message)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .networkError(let message):
            try container.encode("network", forKey: .type)
            try container.encode(message, forKey: .message)
        case .serverError(let code, let message):
            try container.encode("server", forKey: .type)
            try container.encode(code, forKey: .code)
            try container.encode(message, forKey: .message)
        case .decodingError(let message):
            try container.encode("decoding", forKey: .type)
            try container.encode(message, forKey: .message)
        case .encodingError(let message):
            try container.encode("encoding", forKey: .type)
            try container.encode(message, forKey: .message)
        case .authenticationError(let message):
            try container.encode("authentication", forKey: .type)
            try container.encode(message, forKey: .message)
        case .authorizationError(let message):
            try container.encode("authorization", forKey: .type)
            try container.encode(message, forKey: .message)
        case .validationError(let errors):
            try container.encode("validation", forKey: .type)
            try container.encode(errors, forKey: .errors)
        case .notFound(let message):
            try container.encode("notFound", forKey: .type)
            try container.encode(message, forKey: .message)
        case .timeout(let message):
            try container.encode("timeout", forKey: .type)
            try container.encode(message, forKey: .message)
        case .unknown(let message):
            try container.encode("unknown", forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}

// MARK: - Factory Methods

extension APIError {
    /// Creates an API error from HTTP response
    static func fromHTTPResponse(_ response: HTTPURLResponse, data: Data? = nil) -> APIError {
        let statusCode = response.statusCode
        
        var message = "HTTP Error \(statusCode)"
        
        // Try to parse error message from response data
        if let data = data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorMessage = json["error"] as? String {
                message = errorMessage
            } else if let errorMessage = json["message"] as? String {
                message = errorMessage
            } else if let errors = json["errors"] as? [String] {
                return .validationError(errors)
            }
        }
        
        switch statusCode {
        case 400...499:
            if statusCode == 401 {
                return .authenticationError(message)
            } else if statusCode == 403 {
                return .authorizationError(message)
            } else if statusCode == 404 {
                return .notFound(message)
            } else if statusCode == 408 {
                return .timeout(message)
            } else {
                return .serverError(statusCode, message)
            }
        case 500...599:
            return .serverError(statusCode, message)
        default:
            return .unknown(message)
        }
    }
    
    /// Creates an API error from network error
    static func fromNetworkError(_ error: Error) -> APIError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .networkError("No internet connection")
            case .timedOut:
                return .timeout("Request timed out")
            case .cannotFindHost, .cannotConnectToHost:
                return .networkError("Cannot connect to server")
            default:
                return .networkError(urlError.localizedDescription)
            }
        } else {
            return .networkError(error.localizedDescription)
        }
    }
}