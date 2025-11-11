import Foundation
import Combine
import SwiftUI

// MARK: - Service State Management

/// Represents the current state of an external service or connector
public enum ServiceState: String, CaseIterable {
    case available = "available"
    case connecting = "connecting"
    case connected = "connected"
    case hold = "hold"
    case unavailable = "unavailable"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .available:
            return "Available"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .hold:
            return "On Hold"
        case .unavailable:
            return "Unavailable"
        case .error:
            return "Error"
        }
    }
    
    var color: Color {
        switch self {
        case .available:
            return .blue
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .hold:
            return .yellow
        case .unavailable:
            return .gray
        case .error:
            return .red
        }
    }
    
    var systemImage: String {
        switch self {
        case .available:
            return "circle.dotted"
        case .connecting:
            return "arrow.clockwise"
        case .connected:
            return "checkmark.circle.fill"
        case .hold:
            return "pause.circle.fill"
        case .unavailable:
            return "xmark.circle"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}

/// Information about why a service is in hold state
public struct HoldStateInfo {
    let reason: String
    let suggestedAction: String
    let canRetry: Bool
    let estimatedResolution: TimeInterval?
    
    static let missingCredentials = HoldStateInfo(
        reason: "Missing authentication credentials",
        suggestedAction: "Configure credentials in Settings",
        canRetry: true,
        estimatedResolution: nil
    )
    
    static let networkUnavailable = HoldStateInfo(
        reason: "Network connection unavailable",
        suggestedAction: "Check internet connection",
        canRetry: true,
        estimatedResolution: 30
    )
    
    static let serviceUnavailable = HoldStateInfo(
        reason: "External service temporarily unavailable",
        suggestedAction: "Service will retry automatically",
        canRetry: false,
        estimatedResolution: 60
    )
    
    static let permissionsRequired = HoldStateInfo(
        reason: "Required permissions not granted",
        suggestedAction: "Grant permissions in Settings",
        canRetry: true,
        estimatedResolution: nil
    )
    
    static let configurationRequired = HoldStateInfo(
        reason: "Service configuration incomplete",
        suggestedAction: "Complete setup in Settings",
        canRetry: true,
        estimatedResolution: nil
    )
}

/// Protocol for services that can be put on hold
@MainActor
public protocol HoldableService: ObservableObject {
    var serviceState: ServiceState { get }
    var holdInfo: HoldStateInfo? { get }
    var lastError: Error? { get }
    
    func putOnHold(reason: HoldStateInfo)
    func resumeFromHold() async throws
    func checkAvailability() async -> Bool
}

/// Central manager for all service states
@MainActor
public class ServiceStateManager: ObservableObject {
    public static let shared = ServiceStateManager()
    
    @Published public var services: [String: ServiceState] = [:]
    @Published public var holdReasons: [String: HoldStateInfo] = [:]
    @Published public var globalState: ServiceState = .available
    
    private var retryTimers: [String: Timer] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupGlobalStateMonitoring()
    }
    
    public func registerService(_ serviceName: String, initialState: ServiceState = .available) {
        services[serviceName] = initialState
        updateGlobalState()
    }
    
    public func updateServiceState(_ serviceName: String, to state: ServiceState, holdInfo: HoldStateInfo? = nil) {
        services[serviceName] = state
        
        if let holdInfo = holdInfo {
            holdReasons[serviceName] = holdInfo
        } else {
            holdReasons.removeValue(forKey: serviceName)
        }
        
        updateGlobalState()
        
        // Set up automatic retry if applicable
        if state == .hold, let holdInfo = holdInfo, holdInfo.canRetry,
           let estimatedResolution = holdInfo.estimatedResolution {
            setupRetryTimer(for: serviceName, after: estimatedResolution)
        }
    }
    
    private func setupRetryTimer(for serviceName: String, after delay: TimeInterval) {
        retryTimers[serviceName]?.invalidate()
        
        retryTimers[serviceName] = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.attemptServiceRetry(serviceName)
            }
        }
    }
    
    private func attemptServiceRetry(_ serviceName: String) {
        // This would be implemented by each service
        updateServiceState(serviceName, to: .connecting)
        
        // Simulate retry attempt
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // This is where each service would implement their retry logic
            self.updateServiceState(serviceName, to: .available)
        }
    }
    
    private func updateGlobalState() {
        let states = Array(services.values)
        
        if states.contains(.error) {
            globalState = .error
        } else if states.contains(.connecting) {
            globalState = .connecting
        } else if states.allSatisfy({ $0 == .connected }) {
            globalState = .connected
        } else if states.contains(.hold) {
            globalState = .hold
        } else if states.contains(.unavailable) {
            globalState = .unavailable
        } else {
            globalState = .available
        }
    }
    
    private func setupGlobalStateMonitoring() {
        // Monitor network connectivity
        // This would integrate with Network framework
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.checkAllServicesAvailability()
                }
            }
            .store(in: &cancellables)
    }
    
    private func checkAllServicesAvailability() async {
        // Check each registered service
        for serviceName in services.keys {
            // This would be implemented by each service
            let isAvailable = await checkServiceAvailability(serviceName)
            
            if !isAvailable && services[serviceName] == .connected {
                updateServiceState(
                    serviceName,
                    to: .hold,
                    holdInfo: .networkUnavailable
                )
            }
        }
    }
    
    private func checkServiceAvailability(_ serviceName: String) async -> Bool {
        // Placeholder - would be implemented by each service
        return true
    }
    
    public func getServiceStatus(_ serviceName: String) -> (state: ServiceState, holdInfo: HoldStateInfo?) {
        let state = services[serviceName] ?? .unavailable
        let holdInfo = holdReasons[serviceName]
        return (state, holdInfo)
    }
    
    public func getAllServicesInHold() -> [String: HoldStateInfo] {
        return services.compactMapValues { state in
            guard state == .hold else { return nil }
            return holdReasons[services.first(where: { $0.value == state })?.key ?? ""] ?? .serviceUnavailable
        }
    }
}

// MARK: - SwiftUI Components

public struct ServiceStateIndicator: View {
    let serviceName: String
    let state: ServiceState
    let holdInfo: HoldStateInfo?
    
    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state.systemImage)
                .foregroundColor(state.color)
                .font(.system(size: 14, weight: .medium))
            
            Text(state.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(state.color)
        }
    }
}

public struct ServiceStatusCard: View {
    let serviceName: String
    @StateObject private var stateManager = ServiceStateManager.shared
    
    public init(serviceName: String) {
        self.serviceName = serviceName
    }
    
    public var body: some View {
        let (state, holdInfo) = stateManager.getServiceStatus(serviceName)
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(serviceName)
                    .font(.headline)
                
                Spacer()
                
                ServiceStateIndicator(
                    serviceName: serviceName,
                    state: state,
                    holdInfo: holdInfo
                )
            }
            
            if let holdInfo = holdInfo, state == .hold {
                VStack(alignment: .leading, spacing: 4) {
                    Text(holdInfo.reason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(holdInfo.suggestedAction)
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    if holdInfo.canRetry {
                        Button("Retry Connection") {
                            Task {
                                stateManager.updateServiceState(serviceName, to: .connecting)
                                // Service-specific retry logic would go here
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Service State Extensions

extension ServiceStateManager {
    // Pre-defined service names
    public static let entraIDService = "EntraID Authentication"
    public static let bluetoothService = "Bluetooth Connectivity"
    public static let nfcService = "NFC Communication"
    public static let healthKitService = "HealthKit Integration"
    public static let supabaseService = "Supabase Backend"
    public static let passwordlessService = "Passwordless Authentication"
    public static let watchConnectivity = "Apple Watch Connectivity"
    
    public func setupDefaultServices() {
        registerService(Self.entraIDService)
        registerService(Self.bluetoothService)
        registerService(Self.nfcService)
        registerService(Self.healthKitService)
        registerService(Self.supabaseService)
        registerService(Self.passwordlessService)
        registerService(Self.watchConnectivity)
    }
}