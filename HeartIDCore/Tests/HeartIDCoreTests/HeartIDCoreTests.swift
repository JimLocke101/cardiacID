//
//  HeartIDCoreTests.swift
//  HeartIDCore
//
//  Unit tests for the HeartID core models and engines.
//

import XCTest
@testable import HeartIDCore

final class HeartVerificationResultTests: XCTestCase {

    func testCombinedScoreCalculation() {
        let result = HeartVerificationResult.verified(match: 0.90, liveness: 0.85)
        // 0.90 * 0.75 + 0.85 * 0.25 = 0.675 + 0.2125 = 0.8875
        XCTAssertEqual(result.combinedScore, 0.8875, accuracy: 0.001)
        XCTAssertTrue(result.isAuthorized)
        XCTAssertTrue(result.isLive)
    }

    func testDeniedResult() {
        let result = HeartVerificationResult.denied(reason: .watchUnreachable)
        XCTAssertEqual(result.combinedScore, 0)
        XCTAssertFalse(result.isAuthorized)
        XCTAssertFalse(result.isLive)
        XCTAssertEqual(result.reasonCodes, [.watchUnreachable])
    }

    func testLowConfidenceNotAuthorized() {
        let result = HeartVerificationResult.verified(match: 0.50, liveness: 0.50)
        // 0.50 * 0.75 + 0.50 * 0.25 = 0.375 + 0.125 = 0.50
        XCTAssertFalse(result.isAuthorized)
    }

    func testClampsToZeroOne() {
        let result = HeartVerificationResult.verified(match: 1.5, liveness: -0.3)
        XCTAssertEqual(result.matchConfidence, 1.0)
        XCTAssertEqual(result.livenessConfidence, 0.0)
    }
}

final class PolicyEngineTests: XCTestCase {

    func testAllowWhenScoreMeetsThreshold() {
        let engine = DefaultHeartAuthPolicyEngine(configuration: .production)
        let result = HeartVerificationResult.verified(match: 0.90, liveness: 0.90)
        let decision = engine.evaluate(result: result, for: .signInToApp)
        XCTAssertEqual(decision.decision, .allow)
    }

    func testDenyWhenScoreZero() {
        let engine = DefaultHeartAuthPolicyEngine(configuration: .production)
        let result = HeartVerificationResult.denied(reason: .watchUnreachable)
        let decision = engine.evaluate(result: result, for: .signInToApp)
        XCTAssertEqual(decision.decision, .deny)
    }

    func testStepUpInRange() {
        let engine = DefaultHeartAuthPolicyEngine(configuration: .production)
        // signInToApp threshold = 0.70, step-up floor = 0.56
        // Need combined score between 0.56 and 0.70
        let result = HeartVerificationResult.verified(match: 0.65, liveness: 0.65)
        // combined = 0.65 * 0.75 + 0.65 * 0.25 = 0.65
        let decision = engine.evaluate(result: result, for: .signInToApp)
        XCTAssertEqual(decision.decision, .requireStepUp)
    }

    func testDenyBelowStepUpFloor() {
        let engine = DefaultHeartAuthPolicyEngine(configuration: .production)
        let result = HeartVerificationResult.verified(match: 0.40, liveness: 0.40)
        // combined = 0.40
        let decision = engine.evaluate(result: result, for: .signInToApp)
        XCTAssertEqual(decision.decision, .deny)
    }

    func testHighSecurityActionRequiresHighScore() {
        let engine = DefaultHeartAuthPolicyEngine(configuration: .production)
        // authorizeHardwareCommand threshold = 0.90
        let result = HeartVerificationResult.verified(match: 0.85, liveness: 0.85)
        // combined = 0.85 — below 0.90
        let decision = engine.evaluate(result: result, for: .authorizeHardwareCommand)
        XCTAssertNotEqual(decision.decision, .allow)
    }
}

final class HeartIdentityEngineTests: XCTestCase {

    func testDeniesWhenWatchUnreachable() async throws {
        let engine = DefaultHeartIdentityEngine()
        let input = CardiacSignalInput(
            matchConfidence: 0.90,
            method: "ecg",
            isActivelyMonitoring: true,
            isAuthenticated: true,
            sampleTimestamp: Date(),
            heartRate: 72,
            isWatchReachable: false
        )
        let result = try await engine.evaluateIdentity(from: input)
        XCTAssertEqual(result.reasonCodes, [.watchUnreachable])
        XCTAssertFalse(result.isAuthorized)
    }

    func testDeniesStaleReading() async throws {
        let engine = DefaultHeartIdentityEngine()
        let input = CardiacSignalInput(
            matchConfidence: 0.90,
            method: "ecg",
            isActivelyMonitoring: true,
            isAuthenticated: true,
            sampleTimestamp: Date().addingTimeInterval(-300), // 5 min ago
            heartRate: 72,
            isWatchReachable: true
        )
        let result = try await engine.evaluateIdentity(from: input)
        XCTAssertEqual(result.reasonCodes, [.staleReading])
    }

    func testSuccessfulVerification() async throws {
        let engine = DefaultHeartIdentityEngine()
        let input = CardiacSignalInput(
            matchConfidence: 0.88,
            method: "ecg",
            isActivelyMonitoring: true,
            isAuthenticated: true,
            sampleTimestamp: Date(),
            heartRate: 72,
            isWatchReachable: true
        )
        let result = try await engine.evaluateIdentity(from: input)
        XCTAssertTrue(result.isAuthorized)
        XCTAssertEqual(result.reasonCodes, [.success])
    }

    func testMockEngineReturnsFixedValues() async throws {
        let mock = MockHeartIdentityEngine(match: 0.95, liveness: 0.92)
        let input = CardiacSignalInput(
            matchConfidence: 0, method: "", isActivelyMonitoring: false,
            isAuthenticated: false, sampleTimestamp: nil, heartRate: nil, isWatchReachable: false
        )
        let result = try await mock.evaluateIdentity(from: input)
        XCTAssertEqual(result.matchConfidence, 0.95)
        XCTAssertEqual(result.livenessConfidence, 0.92)
    }
}

final class TrustLevelTests: XCTestCase {

    func testComparable() {
        XCTAssertTrue(TrustLevel.denied < TrustLevel.unverified)
        XCTAssertTrue(TrustLevel.unverified < TrustLevel.recentlyVerified)
        XCTAssertTrue(TrustLevel.recentlyVerified < TrustLevel.elevatedTrust)
    }
}

final class SessionTrustStateTests: XCTestCase {

    func testInitialStateIsInvalid() {
        let state = SessionTrustState.initial
        XCTAssertFalse(state.isValid(for: .signInToApp))
    }

    func testRecentlyVerifiedIsValidForSignIn() {
        let state = SessionTrustState(
            currentState: .recentlyVerified,
            lastVerified: Date(),
            lastConfidenceScore: 0.80
        )
        XCTAssertTrue(state.isValid(for: .signInToApp))
    }

    func testExpiredIsInvalid() {
        let state = SessionTrustState(
            currentState: .expired,
            lastVerified: Date(),
            lastConfidenceScore: 0.80
        )
        XCTAssertFalse(state.isValid(for: .signInToApp))
    }
}

final class ProtectedActionTests: XCTestCase {

    func testAllCasesHaveDisplayNames() {
        for action in ProtectedAction.allCases {
            XCTAssertFalse(action.displayName.isEmpty)
            XCTAssertFalse(action.systemImage.isEmpty)
        }
    }

    func testThresholdsAreInRange() {
        for action in ProtectedAction.allCases {
            XCTAssertGreaterThanOrEqual(action.defaultThreshold, 0.50)
            XCTAssertLessThanOrEqual(action.defaultThreshold, 1.0)
        }
    }
}
