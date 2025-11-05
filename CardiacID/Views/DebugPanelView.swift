import SwiftUI

/// Debug panel for development and testing
struct DebugPanelView: View {
    @State private var isExpanded = false
    @State private var logs: [String] = []
    @State private var showingLogs = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Debug header
            HStack {
                Image(systemName: "ladybug.fill")
                    .foregroundColor(.orange)
                
                Text("Debug Panel")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // App info
                    VStack(alignment: .leading, spacing: 4) {
                        Text("App Information")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text(DebugConfig.debugInfo)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Debug controls
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Debug Controls")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Button("Clear Logs") {
                            logs.removeAll()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Export Logs") {
                            exportLogs()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Test Authentication") {
                            testAuthentication()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Test Watch Connection") {
                            testWatchConnection()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Divider()
                    
                    // Log viewer
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Recent Logs")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            Button("View All") {
                                showingLogs = true
                            }
                            .font(.caption)
                        }
                        
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(logs.suffix(10).enumerated()), id: \.offset) { index, log in
                                    Text(log)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(maxHeight: 100)
                        .background(Color(.systemGray6))
                        .cornerRadius(4)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .shadow(radius: 2)
            }
        }
        .sheet(isPresented: $showingLogs) {
            LogsView(logs: logs)
        }
        .onAppear {
            loadLogs()
        }
    }
    
    private func loadLogs() {
        // In a real implementation, you would load logs from a persistent store
        logs = [
            "App launched",
            "Authentication manager initialized",
            "Watch connectivity service started",
            "HealthKit permissions requested"
        ]
    }
    
    private func exportLogs() {
        let logText = logs.joined(separator: "\n")
        let activityVC = UIActivityViewController(activityItems: [logText], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
    
    private func testAuthentication() {
        debugLog.auth("Debug panel: Testing authentication")
        // Add test authentication logic here
    }
    
    private func testWatchConnection() {
        debugLog.watch("Debug panel: Testing watch connection")
        // Add test watch connection logic here
    }
}

/// Full logs view
struct LogsView: View {
    let logs: [String]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(logs.enumerated()), id: \.offset) { index, log in
                        Text(log)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Debug Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    DebugPanelView()
        .padding()
}



