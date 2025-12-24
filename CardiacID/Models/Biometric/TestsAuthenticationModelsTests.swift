//
//  AuthenticationModelsTests.swift
//  CardiacID Tests
//
//  Created by CardiacID Team on 12/23/25.
//

import Testing
import Foundation

@Suite("Authentication Models Tests")
struct AuthenticationModelsTests {
    
    @Test("AuthenticationResult initializes correctly")
    func authenticationResultInitialization() throws {
        let method: AuthenticationResult.AuthenticationMethod = .ecgSingle
        let factors = AuthenticationResult.DecisionFactors(
            templateMatch: 0.95,
            livenessScore: 0.88,
            deviceTrust: 0.92,
            wristDetection: true,
            timeSinceLastECG: 120.0,
            environmentalFactors: 0.85
        )
        
        let result = AuthenticationResult(
            success: true,
            confidenceScore: 0.90,
            method: method,
            decisionFactors: factors,
            timestamp: Date(),
            requiresStepUp: false
        )
        
        #expect(result.success == true)
        #expect(result.confidenceScore == 0.90)
        #expect(result.method == .ecgSingle)
        #expect(result.requiresStepUp == false)
    }
    
    @Test("ConfidenceThresholds default values are correct")
    func confidenceThresholdsDefaults() throws {
        let thresholds = ConfidenceThresholds.default
        
        #expect(thresholds.fullAccess == 0.85)
        #expect(thresholds.conditionalAccess == 0.75)
        #expect(thresholds.requireStepUp == 0.75)
        #expect(thresholds.minimumAccuracy == 0.96)
    }
    
    @Test("BatteryManagementSettings calculates intervals correctly")
    func batteryManagementSettingsCalculation() throws {
        let settings = BatteryManagementSettings.default
        let expectedInterval = 15.0 * 60.0 // 15 minutes in seconds
        
        #expect(settings.confidenceCheckInterval == expectedInterval)
        #expect(settings.ppgUsageMultiplier == 1.0)
    }
    
    @Test("AuthenticationSession initializes with correct defaults")
    func authenticationSessionInitialization() throws {
        let userId = "test-user-123"
        let confidenceScore = 0.85
        let authMethod = "heart_pattern"
        
        let session = AuthenticationSession(
            userId: userId,
            confidenceScore: confidenceScore,
            authMethod: authMethod
        )
        
        #expect(session.userId == userId)
        #expect(session.confidenceScore == confidenceScore)
        #expect(session.authMethod == authMethod)
        #expect(session.isActive == true)
        #expect(session.backgroundVerificationCount == 0)
        #expect(session.locationConsistent == true)
        #expect(session.behaviorNormal == true)
        #expect(session.deviceTrusted == true)
    }
    
    @Test("IntegrationMode enum has correct cases")
    func integrationModeEnum() throws {
        let allCases = IntegrationMode.allCases
        
        #expect(allCases.contains(.local))
        #expect(allCases.contains(.entraID))
        #expect(allCases.contains(.pacs))
        #expect(allCases.contains(.healthcare))
        #expect(allCases.contains(.custom))
        
        // Test that local mode is not demo
        #expect(IntegrationMode.local.isDemo == false)
    }
    
    @Test("ConfidenceDegradationConstants have expected values")
    func confidenceDegradationConstants() throws {
        #expect(ConfidenceDegradationConstants.ecgDegradationRate == 0.00001)
        #expect(ConfidenceDegradationConstants.degradationInterval == 360.0)
        #expect(ConfidenceDegradationConstants.recentECGBufferTime == 240.0)
        #expect(ConfidenceDegradationConstants.minimumConfidenceFloor == 0.70)
    }
}

@Suite("WatchAuthenticationResult Tests")
struct WatchAuthenticationResultTests {
    
    @Test("WatchAuthenticationResult validates correctly")
    func watchAuthResultValidation() throws {
        // Test valid result
        let validResult = WatchAuthenticationResult(
            isSuccess: true,
            token: "valid-token-123",
            refreshToken: "refresh-token-456",
            expiresAt: Date().addingTimeInterval(3600), // 1 hour from now
            errorMessage: nil,
            method: "entra_id"
        )
        
        #expect(validResult.isValid == true)
        
        // Test invalid result - no token
        let invalidResult = WatchAuthenticationResult(
            isSuccess: true,
            token: nil,
            refreshToken: nil,
            expiresAt: nil,
            errorMessage: nil,
            method: "entra_id"
        )
        
        #expect(invalidResult.isValid == false)
        
        // Test expired result
        let expiredResult = WatchAuthenticationResult(
            isSuccess: true,
            token: "valid-token-123",
            refreshToken: "refresh-token-456",
            expiresAt: Date().addingTimeInterval(-3600), // 1 hour ago
            errorMessage: nil,
            method: "entra_id"
        )
        
        #expect(expiredResult.isValid == false)
    }
    
    @Test("WatchAuthenticationResult handles empty tokens")
    func watchAuthResultEmptyToken() throws {
        let result = WatchAuthenticationResult(
            isSuccess: true,
            token: "",
            refreshToken: nil,
            expiresAt: nil,
            errorMessage: nil,
            method: "entra_id"
        )
        
        #expect(result.isValid == false)
    }
}

@Suite("Authentication Action Tests")
struct AuthenticationActionTests {
    
    @Test("AuthenticationAction creates correctly")
    func authenticationActionCreation() throws {
        let action = AuthenticationAction(
            actionType: .doorAccess,
            requiredConfidence: 0.85,
            requiresECG: true,
            description: "Access to secure door"
        )
        
        #expect(action.actionType == .doorAccess)
        #expect(action.requiredConfidence == 0.85)
        #expect(action.requiresECG == true)
        #expect(action.description == "Access to secure door")
    }
}