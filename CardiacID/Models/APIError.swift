//
//  APIError.swift
//  CardiacID
//
//  API Error types for network operations
//

import Foundation

/// Standard API error type for CardiacID services
enum APIError: Error, LocalizedError {
    case networkError(Error)
    case invalidResponse
    case unauthorized
    case authenticationError(String)
    case notFound
    case serverError(Int, String?)
    case decodingError(Error)
    case invalidData
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Unauthorized - please sign in again"
        case .authenticationError(let message):
            return "Authentication error: \(message)"
        case .notFound:
            return "Resource not found"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown error")"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .invalidData:
            return "Invalid data received"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}
