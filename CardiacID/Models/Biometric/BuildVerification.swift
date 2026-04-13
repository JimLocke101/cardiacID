//
//  BuildVerification.swift
//  CardiacID
//
//  Build verification to ensure no compilation conflicts
//  Created by CardiacID Team on 12/23/25.
//

import Foundation
import UIKit

/// This file verifies that all types can be imported and used without conflicts
class BuildVerification {

    @MainActor
    static func verifyTypeResolution() {
        // Test that we can create both authentication result types without conflicts

        // 1. AuthenticationResult from AuthenticationModels.swift
        let authResult = AuthenticationResult(
            success: true,
            confidenceScore: 0.95,
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

        // 2. WatchAuthenticationResult from WatchConnectivityService.swift
        let watchResult = WatchAuthenticationResult(
            isSuccess: true,
            token: "test-token",
            refreshToken: "test-refresh",
            expiresAt: Date().addingTimeInterval(3600),
            errorMessage: nil,
            method: "test"
        )

        // 3. Test UI device access (should not fail with missing UIKit)
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"

        // 4. Test that confidence thresholds are accessible
        let thresholds = ConfidenceThresholds.default

        // 5. Test integration modes
        let mode = IntegrationMode.local

        print("Build verification passed:")
        print("   - AuthenticationResult: \(authResult.success)")
        print("   - WatchAuthenticationResult: \(watchResult.isSuccess)")
        print("   - Device ID available: \(!deviceId.isEmpty)")
        print("   - Thresholds accessible: \(thresholds.fullAccess > 0)")
        print("   - Integration modes: \(mode.rawValue)")

        // Test WatchConnectivityService without property access
        let serviceExists = WatchConnectivityServiceVerification.verifyServiceExists()
        let serviceMethodsWork = WatchConnectivityServiceVerification.verifyServiceMethods()
        print("   - WatchConnectivityService exists: \(serviceExists)")
        print("   - WatchConnectivityService methods: \(serviceMethodsWork)")
    }
    
    static func verifyAsyncSupport() async {
        // Test that async functions can be called properly
        print("✅ Async support verification initiated")
        
        // Test basic async/await syntax without specific service calls
        await Task.yield()
        
        print("✅ Async support verified")
    }
}

/// Service verification without direct property access
class WatchConnectivityServiceVerification {

    /// Verify that WatchConnectivityService exists and can be instantiated
    @MainActor
    static func verifyServiceExists() -> Bool {
        _ = WatchConnectivityService.shared
        return true
    }

    /// Test that service methods can be called without compilation errors
    @MainActor
    static func verifyServiceMethods() -> Bool {
        let service = WatchConnectivityService.shared

        // Test that we can call public methods without runtime errors
        // Note: sendMessage is private, so we test public methods instead
        service.startMonitoring()
        service.stopMonitoring()

        return true
    }
}