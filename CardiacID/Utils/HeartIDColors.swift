import SwiftUI

/// Color scheme for HeartID app following the brand guidelines
struct HeartIDColors {
    // Primary branded colors
    let accent = Color(hex: "#FBBF24") // HeartID branding yellow
    let primary = Color(hex: "#171717") // Near black for backgrounds
    
    // UI colors
    let background = Color(hex: "#121212") // Dark background
    let card = Color(hex: "#1E1E1E") // Slightly lighter for cards
    let surface = Color(hex: "#1E1E1E") // Surface color (same as card)
    let text = Color.white
    let secondary = Color(hex: "#A0A0A0") // Secondary text
    
    // Status colors
    let success = Color(hex: "#4CAF50")
    let warning = Color(hex: "#FBBF24") // HeartID branding yellow
    let error = Color(hex: "#F44336")
    
    // Gradients
    var accentGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [accent, accent.opacity(0.8)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var backgroundGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [primary, background]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// Extension to create colors from hex values
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
