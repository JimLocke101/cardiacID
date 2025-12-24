//
//  WatchConnectivityServiceTests.swift
//  CardiacID Tests
//
//  Created by CardiacID Team on 12/23/25.
//

import Testing
import Foundation

@Suite("WatchConnectivityService Tests")
struct WatchConnectivityServiceTests {
    
    @Test("WatchConnectivityService initializes correctly")
    func watchConnectivityServiceInitialization() throws {
        let service = WatchConnectivityService.shared
        
        #expect(service.isWatchConnected == false) // Default state
        #expect(service.lastHeartRate == nil) // Default state
    }
    
    @Test("WatchAuthenticationResult and AuthenticationResult are distinct types")
    func distinctAuthenticationResultTypes() throws {
        // This test ensures we can create both types without conflicts
        
        // Create WatchAuthenticationResult (from WatchConnectivityService)
        let watchResult = WatchAuthenticationResult(
            isSuccess: true,
            token: "watch-token",
            refreshToken: "watch-refresh",
            expiresAt: Date().addingTimeInterval(3600),
            errorMessage: nil,
            method: "entra_id"
        )
        
        // Create AuthenticationResult (from AuthenticationModels)
        let authResult = AuthenticationResult(
            success: true,
            confidenceScore: 0.90,
            method: .ecgSingle,
            decisionFactors: AuthenticationResult.DecisionFactors(
                templateMatch: 0.95,
                livenessScore: 0.88,
                deviceTrust: 0.92,
                wristDetection: true,
                timeSinceLastECG: 120.0,
                environmentalFactors: 0.85
            ),
            timestamp: Date(),
            requiresStepUp: false
        )
        
        // Verify both types exist and have distinct properties
        #expect(watchResult.isSuccess == true)
        #expect(watchResult.token == "watch-token")
        
        #expect(authResult.success == true)
        #expect(authResult.confidenceScore == 0.90)
        
        // Verify they are different types
        #expect(type(of: watchResult) != type(of: authResult))
    }
    
    @Test("WatchConnectivityError cases are available")
    func watchConnectivityErrorCases() throws {
        let errors: [WatchConnectivityError] = [
            .sessionNotActivated,
            .watchNotReachable,
            .messageSendFailed("Test error"),
            .authenticationFailed("Auth failed")
        ]
        
        #expect(errors.count == 4)
        
        // Test localized descriptions
        for error in errors {
            #expect(!error.localizedDescription.isEmpty)
        }
    }
}