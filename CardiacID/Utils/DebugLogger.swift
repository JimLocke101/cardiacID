import Foundation
import os.log

/// Debug logging utility for HeartID Mobile app
class DebugLogger {
    static let shared = DebugLogger()
    
    private let logger = Logger(subsystem: "com.heartid.mobile", category: "debug")
    private let isDebugMode = true // Set to false for production
    
    private init() {}
    
    /// Log debug information
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard isDebugMode else { return }
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        logger.debug("🐛 [\(fileName):\(line)] \(function): \(message)")
        print("🐛 [\(fileName):\(line)] \(function): \(message)")
    }
    
    /// Log info messages
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        logger.info("ℹ️ [\(fileName):\(line)] \(function): \(message)")
        print("ℹ️ [\(fileName):\(line)] \(function): \(message)")
    }
    
    /// Log warning messages
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        logger.warning("⚠️ [\(fileName):\(line)] \(function): \(message)")
        print("⚠️ [\(fileName):\(line)] \(function): \(message)")
    }
    
    /// Log error messages
    func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let errorMessage = error != nil ? " - Error: \(error!.localizedDescription)" : ""
        logger.error("❌ [\(fileName):\(line)] \(function): \(message)\(errorMessage)")
        print("❌ [\(fileName):\(line)] \(function): \(message)\(errorMessage)")
    }
    
    /// Log authentication events
    func auth(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        logger.info("🔐 [\(fileName):\(line)] \(function): \(message)")
        print("🔐 [\(fileName):\(line)] \(function): \(message)")
    }
    
    /// Log network events
    func network(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        logger.info("🌐 [\(fileName):\(line)] \(function): \(message)")
        print("🌐 [\(fileName):\(line)] \(function): \(message)")
    }
    
    /// Log watch connectivity events
    func watch(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        logger.info("⌚ [\(fileName):\(line)] \(function): \(message)")
        print("⌚ [\(fileName):\(line)] \(function): \(message)")
    }
    
    /// Log health data events
    func health(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        logger.info("❤️ [\(fileName):\(line)] \(function): \(message)")
        print("❤️ [\(fileName):\(line)] \(function): \(message)")
    }
}

/// Convenience global logger instance
let debugLog = DebugLogger.shared



