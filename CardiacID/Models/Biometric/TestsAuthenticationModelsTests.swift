//
//  AuthenticationModelsTests.swift
//  CardiacID Tests
//
//  Created by CardiacID Team on 12/23/25.
//

import XCTest
import Foundation

class AuthenticationModelsTests: XCTestCase {
    
    func testAuthenticationResultInitialization() throws {
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
        
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.confidenceScore, 0.90, accuracy: 0.01)
        XCTAssertEqual(result.method, .ecgSingle)
        XCTAssertFalse(result.requiresStepUp)
    }
    
    func testConfidenceThresholdsDefaults() throws {
        let thresholds = ConfidenceThresholds.default
        
        XCTAssertEqual(thresholds.fullAccess, 0.85, accuracy: 0.01)
        XCTAssertEqual(thresholds.conditionalAccess, 0.75, accuracy: 0.01)
        XCTAssertEqual(thresholds.requireStepUp, 0.75, accuracy: 0.01)
        XCTAssertEqual(thresholds.minimumAccuracy, 0.96, accuracy: 0.01)
    }
    
    func testBatteryManagementSettingsCalculation() throws {
        let settings = BatteryManagementSettings.default
        let expectedInterval = 15.0 * 60.0 // 15 minutes in seconds
        
        XCTAssertEqual(settings.confidenceCheckInterval, expectedInterval, accuracy: 0.1)
        XCTAssertEqual(settings.ppgUsageMultiplier, 1.0, accuracy: 0.01)
    }
    
    func testAuthenticationSessionInitialization() throws {
        let userId = "test-user-123"
        let confidenceScore = 0.85
        let authMethod = "heart_pattern"
        
        let session = AuthenticationSession(
            userId: userId,
            confidenceScore: confidenceScore,
            authMethod: authMethod
        )
        
        XCTAssertEqual(session.userId, userId)
        XCTAssertEqual(session.confidenceScore, confidenceScore, accuracy: 0.01)
        XCTAssertEqual(session.authMethod, authMethod)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.backgroundVerificationCount, 0)
        XCTAssertTrue(session.locationConsistent)
        XCTAssertTrue(session.behaviorNormal)
        XCTAssertTrue(session.deviceTrusted)
    }
    
    func testIntegrationModeEnum() throws {
        let allCases = IntegrationMode.allCases
        
        XCTAssertTrue(allCases.contains(.local))
        XCTAssertTrue(allCases.contains(.entraID))
        XCTAssertTrue(allCases.contains(.pacs))
        XCTAssertTrue(allCases.contains(.healthcare))
        XCTAssertTrue(allCases.contains(.custom))
        
        // Test that local mode is not demo
        XCTAssertFalse(IntegrationMode.local.isDemo)
    }
    
    func testConfidenceDegradationConstants() throws {
        XCTAssertEqual(ConfidenceDegradationConstants.ecgDegradationRate, 0.00001, accuracy: 0.00001)
        XCTAssertEqual(ConfidenceDegradationConstants.degradationInterval, 360.0, accuracy: 0.1)
        XCTAssertEqual(ConfidenceDegradationConstants.recentECGBufferTime, 240.0, accuracy: 0.1)
        XCTAssertEqual(ConfidenceDegradationConstants.minimumConfidenceFloor, 0.70, accuracy: 0.01)
    }
}

class WatchAuthenticationResultTests: XCTestCase {
    
    func testWatchAuthResultValidation() throws {
        // Test valid result
        let validResult = WatchAuthenticationResult(
            isSuccess: true,
            token: "valid-token-123",
            refreshToken: "refresh-token-456",
            expiresAt: Date().addingTimeInterval(3600), // 1 hour from now
            errorMessage: nil,
            method: "entra_id"
        )
        
        XCTAssertTrue(validResult.isValid)
        
        // Test invalid result - no token
        let invalidResult = WatchAuthenticationResult(
            isSuccess: true,
            token: nil,
            refreshToken: nil,
            expiresAt: nil,
            errorMessage: nil,
            method: "entra_id"
        )
        
        XCTAssertFalse(invalidResult.isValid)
        
        // Test expired result
        let expiredResult = WatchAuthenticationResult(
            isSuccess: true,
            token: "valid-token-123",
            refreshToken: "refresh-token-456",
            expiresAt: Date().addingTimeInterval(-3600), // 1 hour ago
            errorMessage: nil,
            method: "entra_id"
        )
        
        XCTAssertFalse(expiredResult.isValid)
    }
    
    func testWatchAuthResultEmptyToken() throws {
        let result = WatchAuthenticationResult(
            isSuccess: true,
            token: "",
            refreshToken: nil,
            expiresAt: nil,
            errorMessage: nil,
            method: "entra_id"
        )
        
        XCTAssertFalse(result.isValid)
    }
}

class AuthenticationActionTests: XCTestCase {
    
    func testAuthenticationActionCreation() throws {
        let action = AuthenticationAction(
            actionType: .doorAccess,
            requiredConfidence: 0.85,
            requiresECG: true,
            description: "Access to secure door"
        )
        
        XCTAssertEqual(action.actionType, .doorAccess)
        XCTAssertEqual(action.requiredConfidence, 0.85, accuracy: 0.01)
        XCTAssertTrue(action.requiresECG)
        XCTAssertEqual(action.description, "Access to secure door")
    }
}