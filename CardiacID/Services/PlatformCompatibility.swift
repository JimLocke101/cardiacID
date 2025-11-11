//
//  PlatformCompatibility.swift
//  HeartID Mobile
//
//  Platform compatibility helpers to resolve cross-platform compilation issues
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

#if canImport(CoreNFC)
import CoreNFC
#endif

// MARK: - Platform Availability

public enum Platform {
    case iOS
    case watchOS
    case macOS
    case tvOS
    
    static var current: Platform {
        #if os(iOS)
        return .iOS
        #elseif os(watchOS)
        return .watchOS
        #elseif os(macOS)
        return .macOS
        #elseif os(tvOS)
        return .tvOS
        #endif
    }
}

// MARK: - Feature Availability

public struct PlatformFeatures {
    static var hasUIKit: Bool {
        #if canImport(UIKit)
        return true
        #else
        return false
        #endif
    }
    
    static var hasBluetooth: Bool {
        #if canImport(CoreBluetooth)
        return true
        #else
        return false
        #endif
    }
    
    static var hasNFC: Bool {
        #if canImport(CoreNFC)
        return true
        #else
        return false
        #endif
    }
    
    static var hasMSAL: Bool {
        #if canImport(MSAL)
        return true
        #else
        return false
        #endif
    }
    
    static var supportsBackgroundTasks: Bool {
        switch Platform.current {
        case .iOS, .macOS:
            return true
        case .watchOS, .tvOS:
            return false
        }
    }
    
    static var supportsUserInteraction: Bool {
        switch Platform.current {
        case .iOS, .macOS:
            return true
        case .watchOS:
            return true
        case .tvOS:
            return false
        }
    }
}

// MARK: - Device Status Compatibility

#if !canImport(UIKit)
// Mock UIDevice for non-UIKit platforms
public struct UIDevice {
    public static let current = UIDevice()
    
    public enum BatteryState: Int {
        case unknown = 0
        case unplugged = 1
        case charging = 2
        case full = 3
    }
    
    public var batteryLevel: Float { return -1.0 }
    public var batteryState: BatteryState { return .unknown }
    public var name: String { return Platform.current.description }
    public var systemVersion: String { return "Unknown" }
}
#endif

extension Platform: CustomStringConvertible {
    public var description: String {
        switch self {
        case .iOS: return "iOS"
        case .watchOS: return "watchOS" 
        case .macOS: return "macOS"
        case .tvOS: return "tvOS"
        }
    }
}

// MARK: - Device Status Helper

public struct iPhoneDeviceStatus {
    public let batteryLevel: Double
    public let isCharging: Bool
    public let deviceName: String
    public let systemVersion: String
    
    public static var current: iPhoneDeviceStatus {
        #if canImport(UIKit) && !os(watchOS)
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        return iPhoneDeviceStatus(
            batteryLevel: Double(device.batteryLevel >= 0 ? device.batteryLevel : 0),
            isCharging: device.batteryState == .charging || device.batteryState == .full,
            deviceName: device.name,
            systemVersion: device.systemVersion
        )
        #else
        return iPhoneDeviceStatus(
            batteryLevel: 1.0,
            isCharging: false,
            deviceName: "Unknown Device",
            systemVersion: "Unknown"
        )
        #endif
    }
}

// MARK: - Bluetooth Compatibility

#if !canImport(CoreBluetooth)
// Mock CoreBluetooth types for platforms that don't support it
public class CBCentralManager {
    public init() {}
}

public class CBPeripheral {
    public var name: String? { return nil }
    public var identifier: UUID { return UUID() }
}

public enum CBManagerState: Int {
    case unknown = 0
    case resetting = 1
    case unsupported = 2
    case unauthorized = 3
    case poweredOff = 4
    case poweredOn = 5
}

public protocol CBCentralManagerDelegate: AnyObject {}
#endif

// MARK: - Error Compatibility

public enum PlatformError: LocalizedError {
    case featureUnavailable(String)
    case platformNotSupported(String)
    case frameworkMissing(String)
    
    public var errorDescription: String? {
        switch self {
        case .featureUnavailable(let feature):
            return "Feature '\(feature)' is not available on this platform"
        case .platformNotSupported(let operation):
            return "Operation '\(operation)' is not supported on \(Platform.current)"
        case .frameworkMissing(let framework):
            return "Required framework '\(framework)' is not available"
        }
    }
}

// MARK: - Async Helpers

public extension Task where Success == Never, Failure == Never {
    /// Platform-safe sleep
    static func platformSleep(seconds: TimeInterval) async {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        } catch {
            // Fallback for platforms that don't support async sleep
            Thread.sleep(forTimeInterval: seconds)
        }
    }
}