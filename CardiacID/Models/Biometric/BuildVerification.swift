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
        
        print("✅ Build verification passed:")
        print("   - AuthenticationResult: \(authResult.success)")
        print("   - WatchAuthenticationResult: \(watchResult.isSuccess)")
        print("   - Device ID available: \(!deviceId.isEmpty)")
        print("   - Thresholds accessible: \(thresholds.fullAccess > 0)")
        print("   - Integration modes: \(mode.rawValue)")
    }
    
    static func verifyAsyncSupport() async {
        // Test that async functions can be called properly
        let service = WatchConnectivityService.shared
        
        // This should compile without "async not supported" errors
        let _ = await service.requestEntraIDAuthentication()
        
        print("✅ Async support verified")
    }
}

/// Test extension to verify no property wrapper issues
extension WatchConnectivityService {
    func testMethodAccess() -> Bool {
        // This should compile without ObservedObject wrapper errors
        return self.isWatchConnected
    }
}