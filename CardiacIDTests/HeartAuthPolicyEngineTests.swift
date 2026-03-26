//
//  HeartAuthPolicyEngineTests.swift
//  CardiacIDTests
//
//  Tests DefaultHeartAuthPolicyEngine against all 6 ProtectedAction types.
//  Uses MockHeartIdentityEngine — no real biometric hardware required.
//  No network calls.
//

import XCTest
@testable import CardiacID

final class HeartAuthPolicyEngineTests: XCTestCase {

    private var engine: DefaultHeartAuthPolicyEngine!

    override func setUp() {
        super.setUp()
        // Use production defaults so threshold values are deterministic
        engine = DefaultHeartAuthPolicyEngine(configuration: .production)
    }

    // MARK: - Production threshold reference
    //
    // signInToApp:              0.70
    // unlockProtectedFile:      0.75
    // beginPasskeyAssertion:    0.80
    // beginPasskeyRegistration: 0.80
    // authorizeSensitiveAction: 0.80
    // authorizeHardwareCommand: 0.90

    // MARK: - Score exactly at threshold → .allow

    func testSignInToApp_exactThreshold_allow() {
        let result = makeResult(combinedTarget: 0.70)
        let decision = engine.evaluate(result: result, for: .signInToApp)
        XCTAssertEqual(decision.decision, .allow)
        XCTAssertEqual(decision.action, .signInToApp)
    }

    func testUnlockProtectedFile_exactThreshold_allow() {
        let decision = engine.evaluate(result: makeResult(combinedTarget: 0.75), for: .unlockProtectedFile)
        XCTAssertEqual(decision.decision, .allow)
    }

    func testBeginPasskeyAssertion_exactThreshold_allow() {
        let decision = engine.evaluate(result: makeResult(combinedTarget: 0.80), for: .beginPasskeyAssertion)
        XCTAssertEqual(decision.decision, .allow)
    }

    func testBeginPasskeyRegistration_exactThreshold_allow() {
        let decision = engine.evaluate(result: makeResult(combinedTarget: 0.80), for: .beginPasskeyRegistration)
        XCTAssertEqual(decision.decision, .allow)
    }

    func testAuthorizeSensitiveAction_exactThreshold_allow() {
        let decision = engine.evaluate(result: makeResult(combinedTarget: 0.80), for: .authorizeSensitiveAction)
        XCTAssertEqual(decision.decision, .allow)
    }

    func testAuthorizeHardwareCommand_exactThreshold_allow() {
        let decision = engine.evaluate(result: makeResult(combinedTarget: 0.90), for: .authorizeHardwareCommand)
        XCTAssertEqual(decision.decision, .allow)
    }

    // MARK: - Score 0.01 below threshold → .deny or .requireStepUp

    func testSignInToApp_justBelowThreshold_notAllow() {
        let decision = engine.evaluate(result: makeResult(combinedTarget: 0.69), for: .signInToApp)
        XCTAssertNotEqual(decision.decision, .allow,
                          "0.69 < 0.70 threshold — must not be .allow")
    }

    func testUnlockProtectedFile_justBelowThreshold_notAllow() {
        let decision = engine.evaluate(result: makeResult(combinedTarget: 0.74), for: .unlockProtectedFile)
        XCTAssertNotEqual(decision.decision, .allow)
    }

    func testBeginPasskeyAssertion_justBelowThreshold_notAllow() {
        let decision = engine.evaluate(result: makeResult(combinedTarget: 0.79), for: .beginPasskeyAssertion)
        XCTAssertNotEqual(decision.decision, .allow)
    }

    func testBeginPasskeyRegistration_justBelowThreshold_notAllow() {
        let decision = engine.evaluate(result: makeResult(combinedTarget: 0.79), for: .beginPasskeyRegistration)
        XCTAssertNotEqual(decision.decision, .allow)
    }

    func testAuthorizeSensitiveAction_justBelowThreshold_notAllow() {
        let decision = engine.evaluate(result: makeResult(combinedTarget: 0.79), for: .authorizeSensitiveAction)
        XCTAssertNotEqual(decision.decision, .allow)
    }

    func testAuthorizeHardwareCommand_justBelowThreshold_notAllow() {
        let decision = engine.evaluate(result: makeResult(combinedTarget: 0.89), for: .authorizeHardwareCommand)
        XCTAssertNotEqual(decision.decision, .allow)
    }

    // MARK: - Zero / nil-equivalent input → .deny (fail closed)

    func testZeroScore_failsClosed_deny() {
        let result = HeartVerificationResult.denied(reason: .watchUnreachable)
        for action in ProtectedAction.allCases {
            let decision = engine.evaluate(result: result, for: action)
            XCTAssertEqual(decision.decision, .deny,
                           "Zero score must fail closed to .deny for \(action.rawValue)")
        }
    }

    func testNegligibleScore_failsClosed_deny() {
        // combinedScore = 0.001 * 0.75 + 0.001 * 0.25 = 0.001 — way below all thresholds
        let result = HeartVerificationResult.verified(match: 0.001, liveness: 0.001)
        for action in ProtectedAction.allCases {
            let decision = engine.evaluate(result: result, for: action)
            XCTAssertEqual(decision.decision, .deny,
                           "Negligible score must .deny for \(action.rawValue)")
        }
    }

    // MARK: - PolicyConfiguration override changes threshold behavior

    func testCustomThreshold_lowerThreshold_allowsPreviouslyDenied() {
        // Default: signInToApp requires 0.70 → 0.65 would be denied
        let defaultDecision = engine.evaluate(result: makeResult(combinedTarget: 0.65), for: .signInToApp)
        XCTAssertNotEqual(defaultDecision.decision, .allow, "0.65 < 0.70 default")

        // Override: lower threshold to 0.60
        var custom = PolicyConfiguration.production
        custom.setThreshold(0.60, for: .signInToApp)
        let customEngine = DefaultHeartAuthPolicyEngine(configuration: custom)
        let customDecision = customEngine.evaluate(result: makeResult(combinedTarget: 0.65), for: .signInToApp)
        XCTAssertEqual(customDecision.decision, .allow, "0.65 >= 0.60 custom threshold")
    }

    func testCustomThreshold_raiseThreshold_deniesPreiouslyAllowed() {
        // Default: signInToApp requires 0.70 → 0.75 would be allowed
        let defaultDecision = engine.evaluate(result: makeResult(combinedTarget: 0.75), for: .signInToApp)
        XCTAssertEqual(defaultDecision.decision, .allow, "0.75 >= 0.70 default")

        // Override: raise threshold to 0.90
        var custom = PolicyConfiguration.production
        custom.setThreshold(0.90, for: .signInToApp)
        let customEngine = DefaultHeartAuthPolicyEngine(configuration: custom)
        let customDecision = customEngine.evaluate(result: makeResult(combinedTarget: 0.75), for: .signInToApp)
        XCTAssertNotEqual(customDecision.decision, .allow, "0.75 < 0.90 raised threshold")
    }

    func testCustomThreshold_clampsToMinimum() {
        var config = PolicyConfiguration.production
        config.setThreshold(0.10, for: .signInToApp) // below 0.50 floor
        XCTAssertGreaterThanOrEqual(config.threshold(for: .signInToApp), 0.50)
    }

    func testCustomThreshold_clampsToMaximum() {
        var config = PolicyConfiguration.production
        config.setThreshold(1.50, for: .signInToApp) // above 1.00 ceiling
        XCTAssertLessThanOrEqual(config.threshold(for: .signInToApp), 1.00)
    }

    // MARK: - Step-up zone (80%–100% of threshold)

    func testStepUpZone_scoreInGrayBand() {
        // authorizeHardwareCommand threshold = 0.90
        // Step-up floor = 0.90 * 0.80 = 0.72
        // Score 0.78 is inside [0.72, 0.90) → requireStepUp
        let decision = engine.evaluate(result: makeResult(combinedTarget: 0.78), for: .authorizeHardwareCommand)
        XCTAssertEqual(decision.decision, .requireStepUp)
    }

    // MARK: - Decision metadata correctness

    func testDecisionCarriesCorrectMetadata() {
        let action = ProtectedAction.unlockProtectedFile
        let decision = engine.evaluate(result: makeResult(combinedTarget: 0.80), for: action)
        XCTAssertEqual(decision.action, action)
        XCTAssertEqual(decision.requiredScore, 0.75, accuracy: 0.001)
        XCTAssertEqual(decision.actualScore, 0.80, accuracy: 0.001)
        XCTAssertFalse(decision.rationale.isEmpty)
    }

    // MARK: - Helper

    /// Build a HeartVerificationResult whose combinedScore equals `combinedTarget`.
    /// Since combinedScore = match * 0.75 + liveness * 0.25,
    /// setting match = liveness = target gives combinedScore = target.
    private func makeResult(combinedTarget: Double) -> HeartVerificationResult {
        .verified(match: combinedTarget, liveness: combinedTarget)
    }
}
