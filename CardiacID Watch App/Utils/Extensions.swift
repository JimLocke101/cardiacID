import Foundation
import SwiftUI
import HealthKit
#if os(watchOS)
import WatchKit
#endif

// MARK: - Color Extensions

extension Color {
    static let heartIDBlue = Color(red: 0.0, green: 0.5, blue: 1.0)
    static let heartIDGreen = Color(red: 0.0, green: 0.8, blue: 0.0)
    static let heartIDRed = Color(red: 1.0, green: 0.2, blue: 0.2)
    static let heartIDOrange = Color(red: 1.0, green: 0.6, blue: 0.0)
    static let heartIDPurple = Color(red: 0.6, green: 0.0, blue: 0.8)
    
    // Authentication status colors
    static let authSuccess = Color.green
    static let authWarning = Color.orange
    static let authError = Color.red
    static let authNeutral = Color.gray
}

// MARK: - View Extensions

extension View {
    func heartIDCard() -> some View {
        self
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
    }
    
    func heartIDButton(style: HeartIDButtonStyle = .primary) -> some View {
        self
            .padding()
            .frame(height: 44)
            .background(style.backgroundColor)
            .foregroundColor(style.foregroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style.borderColor, lineWidth: 1)
            )
    }
    
    func heartIDProgressCircle(progress: Double, color: Color = .blue) -> some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                .frame(width: 80, height: 80)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
            
            Text("\(Int(progress * 100))%")
                .font(.headline)
                .fontWeight(.bold)
        }
    }
    
    func heartIDIcon(_ name: String, size: CGFloat = 24, color: Color = .primary) -> some View {
        Image(systemName: name)
            .font(.system(size: size))
            .foregroundColor(color)
    }
}

// MARK: - Button Style

enum HeartIDButtonStyle {
    case primary
    case secondary
    case success
    case warning
    case error
    case disabled
    
    var backgroundColor: Color {
        switch self {
        case .primary:
            return .blue
        case .secondary:
            return .gray.opacity(0.1)
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        case .disabled:
            return .gray.opacity(0.3)
        }
    }
    
    var foregroundColor: Color {
        switch self {
        case .primary, .success, .error:
            return .white
        case .secondary, .warning:
            return .primary
        case .disabled:
            return .gray
        }
    }
    
    var borderColor: Color {
        switch self {
        case .primary:
            return .blue.opacity(0.3)
        case .secondary:
            return .gray.opacity(0.2)
        case .success:
            return .green.opacity(0.3)
        case .warning:
            return .orange.opacity(0.3)
        case .error:
            return .red.opacity(0.3)
        case .disabled:
            return .gray.opacity(0.2)
        }
    }
}

// MARK: - Date Extensions

extension Date {
    func timeAgo() -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(self)
        
        if timeInterval < 60 {
            return "Just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(timeInterval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
    
    func formattedString() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
    
    func isToday() -> Bool {
        Calendar.current.isDateInToday(self)
    }
    
    func isYesterday() -> Bool {
        Calendar.current.isDateInYesterday(self)
    }
}

// MARK: - Array Extensions

extension Array where Element == Double {
    func mean() -> Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
    
    func median() -> Double {
        guard !isEmpty else { return 0 }
        let sortedArray = sorted()
        let count = sortedArray.count
        
        if count % 2 == 0 {
            return (sortedArray[count / 2 - 1] + sortedArray[count / 2]) / 2
        } else {
            return sortedArray[count / 2]
        }
    }
    
    func standardDeviation() -> Double {
        guard count > 1 else { return 0 }
        let mean = self.mean()
        let variance = map { pow($0 - mean, 2) }.reduce(0, +) / Double(count - 1)
        return sqrt(variance)
    }
    
    func range() -> Double {
        guard !isEmpty else { return 0 }
        return (self.max() ?? 0) - (self.min() ?? 0)
    }
    
    func normalized() -> [Double] {
        guard !isEmpty else { return [] }
        let min = self.min() ?? 0
        let max = self.max() ?? 1
        let range = max - min
        
        guard range > 0 else { return Array(repeating: 0, count: count) }
        
        return map { ($0 - min) / range }
    }
}

// MARK: - String Extensions

extension String {
    func localized() -> String {
        return NSLocalizedString(self, comment: "")
    }
    
    func isValidEmail() -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: self)
    }
    
    func base64Encoded() -> String? {
        return data(using: .utf8)?.base64EncodedString()
    }
    
    func base64Decoded() -> String? {
        guard let data = Data(base64Encoded: self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Data Extensions

extension Data {
    func hexString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
    
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            if let byte = UInt8(hexString[index..<nextIndex], radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        
        self = data
    }
}

// MARK: - UserDefaults Extensions

extension UserDefaults {
    func setCodable<T: Codable>(_ object: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(object) {
            set(data, forKey: key)
        }
    }
    
    func getCodable<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - NotificationCenter Extensions

extension NotificationCenter {
    func post(name: Notification.Name, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
        NotificationCenter.default.post(name: name, object: object, userInfo: userInfo)
    }
}

// MARK: - DispatchQueue Extensions

extension DispatchQueue {
    static func mainAsync(execute: @escaping () -> Void) {
        if Thread.isMainThread {
            execute()
        } else {
            main.async(execute: execute)
        }
    }
}

// MARK: - View Modifiers

struct HeartIDCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
    }
}

struct HeartIDButtonModifier: ViewModifier {
    let style: HeartIDButtonStyle
    
    func body(content: Content) -> some View {
        content
            .padding()
            .frame(height: 44)
            .background(style.backgroundColor)
            .foregroundColor(style.foregroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style.borderColor, lineWidth: 1)
            )
    }
}

// MARK: - Animation Extensions

extension Animation {
    static let heartIDBounce = Animation.interpolatingSpring(stiffness: 300, damping: 20)
    static let heartIDFade = Animation.easeInOut(duration: 0.3)
    static let heartIDSlide = Animation.easeInOut(duration: 0.3)
}

// MARK: - Haptic Feedback Extensions

#if os(iOS)
extension UIImpactFeedbackGenerator {
    static func heartIDImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

extension UINotificationFeedbackGenerator {
    static func heartIDNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}
#else
// WatchOS haptic feedback
extension WKInterfaceDevice {
    static func heartIDImpact() {
        WKInterfaceDevice.current().play(.click)
    }
    
    static func heartIDNotification(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
}
#endif


