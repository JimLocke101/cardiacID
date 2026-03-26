//
//  SessionTrustManagerTests.swift
//  CardiacIDTests
//
//  Tests DefaultSessionTrustManager trust state transitions and expiry.
//  Uses MockHeartIdentityEngine — no real biometric hardware.
//  No network calls.
//

import XCTest
@testable import CardiacID

@MainActor
final class SessionTrustManagerTests: XCTestCase {

    private var manager: DefaultSessionTrustManager!

    override func setUp() async throws {
        manager = DefaultSessionTrustManager()
    }

    // MARK: - Fresh manager → .unverified

    func testFreshManager_isUnverified() {
        XCTAssertEqual(manager.state.currentState, .unverified)
        XCTAssertNil(manager.state.lastVerified)
        XCTAssertEqual(manager.state.lastConfidenceScore, 0)
    }

    // MARK: - Record high-confidence result → .recentlyVerified

    func testRecordMediumConfidence_recentlyVerified() {
        // combinedScore = 0.80 (above 0.70 authorized threshold, below 0.90 elevated)
        let result = HeartVerificationResult.verified(match: 0.80, liveness: 0.80)
        manager.recordVerification(result)

        XCTAssertEqual(manager.state.currentState, .recentlyVerified)
        XCTAssertNotNil(manager.state.lastVerified)
        XCTAssertEqual(manager.state.lastConfidenceScore, result.combinedScore, accuracy: 0.001)
    }

    // MARK: - elevatedTrust requires combinedScore >= 0.90

    func testRecordHighConfidence_elevatedTrust() {
        // combinedScore = 0.95 → elevated
        let result = HeartVerificationResult.verified(match: 0.95, liveness: 0.95)
        manager.recordVerification(result)
        XCTAssertEqual(manager.state.currentState, .elevatedTrust)
    }

    func testRecordJustBelowElevated_recentlyVerified() {
        // combinedScore = 0.89 → recently verified, NOT elevated
        let result = HeartVerificationResult.verified(match: 0.89, liveness: 0.89)
        manager.recordVerification(result)
        XCTAssertEqual(manager.state.currentState, .recentlyVerified,
                       "0.89 < 0.90 should be recentlyVerified, not elevatedTrust")
    }

    func testRecordExactlyElevatedThreshold_elevatedTrust() {
        // combinedScore = 0.90 → elevated
        let result = HeartVerificationResult.verified(match: 0.90, liveness: 0.90)
        manager.recordVerification(result)
        XCTAssertEqual(manager.state.currentState, .elevatedTrust)
    }

    // MARK: - Denied result → .denied

    func testRecordDeniedResult_denied() {
        let result = HeartVerificationResult.denied(reason: .lowConfidence)
        manager.recordVerification(result)
        XCTAssertEqual(manager.state.currentState, .denied)
    }

    func testRecordBelowAuthorized_denied() {
        // combinedScore = 0.50 → isAuthorized is false (< 0.70)
        let result = HeartVerificationResult.verified(match: 0.50, liveness: 0.50)
        XCTAssertFalse(result.isAuthorized)
        manager.recordVerification(result)
        XCTAssertEqual(manager.state.currentState, .denied)
    }

    // MARK: - Simulate 5 min elapsed → .expired (via refreshIfNeeded)

    func testRecentlyVerified_expiresAfter5Minutes() {
        let result = HeartVerificationResult.verified(match: 0.80, liveness: 0.80)
        manager.recordVerification(result)
        XCTAssertEqual(manager.state.currentState, .recentlyVerified)

        // Back-date lastVerified by 301 seconds (> 300 s window)
        manager._testBackdateLastVerified(by: 301)

        // currentTrust triggers refreshIfNeeded internally
        let trust = manager.currentTrust(for: .signInToApp)
        XCTAssertEqual(trust.currentState, .expired,
                       "recentlyVerified should expire after 5 minutes")
    }

    func testElevatedTrust_expiresAfter15Minutes() {
        let result = HeartVerificationResult.verified(match: 0.95, liveness: 0.95)
        manager.recordVerification(result)
        XCTAssertEqual(manager.state.currentState, .elevatedTrust)

        // Back-date by 901 seconds (> 900 s window)
        manager._testBackdateLastVerified(by: 901)

        let trust = manager.currentTrust(for: .authorizeHardwareCommand)
        XCTAssertEqual(trust.currentState, .expired)
    }

    func testElevatedTrust_doesNotExpireBefore15Minutes() {
        let result = HeartVerificationResult.verified(match: 0.95, liveness: 0.95)
        manager.recordVerification(result)

        // Back-date by only 600 seconds (< 900 s window)
        manager._testBackdateLastVerified(by: 600)

        let trust = manager.currentTrust(for: .authorizeHardwareCommand)
        XCTAssertEqual(trust.currentState, .elevatedTrust,
                       "Should not expire before 15 min")
    }

    // MARK: - invalidate() → .unverified immediately

    func testInvalidate_resetsToUnverified() {
        let result = HeartVerificationResult.verified(match: 0.95, liveness: 0.95)
        manager.recordVerification(result)
        XCTAssertEqual(manager.state.currentState, .elevatedTrust)

        manager.invalidate()

        XCTAssertEqual(manager.state.currentState, .unverified)
        XCTAssertNil(manager.state.lastVerified)
        XCTAssertEqual(manager.state.lastConfidenceScore, 0)
    }

    func testInvalidate_fromDenied_resetsToUnverified() {
        manager.recordVerification(.denied(reason: .watchUnreachable))
        XCTAssertEqual(manager.state.currentState, .denied)

        manager.invalidate()
        XCTAssertEqual(manager.state.currentState, .unverified)
    }

    // MARK: - isValid(for:) gating

    func testUnverified_isNotValidForAnyAction() {
        for action in ProtectedAction.allCases {
            XCTAssertFalse(manager.state.isValid(for: action),
                           "Unverified should not be valid for \(action.rawValue)")
        }
    }

    func testRecentlyVerified_isValidForLowSecurityActions() {
        manager.recordVerification(.verified(match: 0.80, liveness: 0.80))
        XCTAssertTrue(manager.state.isValid(for: .signInToApp))
        XCTAssertTrue(manager.state.isValid(for: .beginPasskeyAssertion))
    }

    func testRecentlyVerified_isNotValidForHighSecurityActions() {
        manager.recordVerification(.verified(match: 0.80, liveness: 0.80))
        // High-security requires elevatedTrust
        XCTAssertFalse(manager.state.isValid(for: .beginPasskeyRegistration))
        XCTAssertFalse(manager.state.isValid(for: .authorizeHardwareCommand))
    }

    func testElevatedTrust_isValidForAllActions() {
        manager.recordVerification(.verified(match: 0.95, liveness: 0.95))
        for action in ProtectedAction.allCases {
            XCTAssertTrue(manager.state.isValid(for: action),
                          "Elevated trust should be valid for \(action.rawValue)")
        }
    }

    // MARK: - Display helpers

    func testConfidencePercentage_formats() {
        manager.recordVerification(.verified(match: 0.87, liveness: 0.87))
        let pct = manager.state.confidencePercentage
        XCTAssertTrue(pct.hasSuffix("%"))
        XCTAssertTrue(pct.contains("87"))
    }

    func testLastVerifiedDescription_neverWhenFresh() {
        XCTAssertEqual(manager.state.lastVerifiedDescription, "Never")
    }
}
