import SwiftUI

struct LaunchScreen: View {
    // Color scheme
    private let colors = HeartIDColors()
    
    // Animation states
    @State private var scale = 0.7
    @State private var opacity = 0.0
    @State private var rotation = -20.0
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(UIColor.systemBackground),
                    Color(UIColor.systemBackground).opacity(0.8),
                    colors.background.opacity(0.6)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Logo
                ZStack {
                    // Pulsing circle
                    Circle()
                        .fill(colors.accent.opacity(0.2))
                        .frame(width: 140, height: 140)
                        .scaleEffect(scale * 1.5)
                    
                    // Heart icon with ECG line
                    HStack(spacing: 0) {
                        // Heart icon
                        Image(systemName: "heart.fill")
                            .font(.system(size: 50))
                            .foregroundColor(colors.accent)
                            .rotationEffect(.degrees(rotation))
                            .offset(x: -5)
                            .zIndex(1)
                        
                        // ECG line
                        HeartRateLine()
                            .stroke(colors.accent, lineWidth: 3)
                            .frame(width: 80, height: 40)
                            .offset(x: -15)
                    }
                    .scaleEffect(scale)
                }
                .opacity(opacity)
                
                // App name
                Text("HeartID")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(colors.text)
                    .opacity(opacity)
                
                // Tagline
                Text("Secure Authentication")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(colors.secondary)
                    .opacity(opacity * 0.8)
                    .padding(.top, -10)
                
                // Loading indicator
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: colors.accent))
                        .scaleEffect(0.8)
                    
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(colors.secondary)
                        .opacity(opacity * 0.6)
                }
                .padding(.top, 20)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
                rotation = 0.0
            }
        }
    }
}

// Custom shape for heart rate line
struct HeartRateLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        let midHeight = height / 2
        
        // Start at left edge
        path.move(to: CGPoint(x: 0, y: midHeight))
        
        // Flat line
        path.addLine(to: CGPoint(x: width * 0.2, y: midHeight))
        
        // ECG spike
        path.addLine(to: CGPoint(x: width * 0.3, y: midHeight - height * 0.4))
        path.addLine(to: CGPoint(x: width * 0.4, y: midHeight + height * 0.4))
        path.addLine(to: CGPoint(x: width * 0.5, y: midHeight - height * 0.2))
        
        // Continue with normal line
        path.addLine(to: CGPoint(x: width * 0.6, y: midHeight))
        path.addLine(to: CGPoint(x: width, y: midHeight))
        
        return path
    }
}

struct LaunchScreen_Previews: PreviewProvider {
    static var previews: some View {
        LaunchScreen()
            .preferredColorScheme(.dark)
    }
}
