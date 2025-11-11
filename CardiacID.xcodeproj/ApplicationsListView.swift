import SwiftUI

struct ApplicationsListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var serviceStateManager = ServiceStateManager.shared
    
    // Mock applications data
    private let applications = [
        EnterpriseApp(
            id: "com.microsoft.office365",
            name: "Microsoft 365",
            icon: "building.2.crop.circle",
            isConnected: true,
            permissions: ["Read", "Write", "Admin"]
        ),
        EnterpriseApp(
            id: "com.salesforce.app",
            name: "Salesforce",
            icon: "cloud.circle",
            isConnected: false,
            permissions: ["Read", "Write"]
        ),
        EnterpriseApp(
            id: "com.slack.app",
            name: "Slack",
            icon: "message.circle",
            isConnected: true,
            permissions: ["Read", "Write", "Notifications"]
        ),
        EnterpriseApp(
            id: "com.zoom.app",
            name: "Zoom",
            icon: "video.circle",
            isConnected: false,
            permissions: ["Camera", "Microphone", "Calendar"]
        )
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Status header
                ServiceStatusBanner()
                
                // Applications list
                List(applications) { app in
                    ApplicationRow(app: app)
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Enterprise Apps")
            .navigationBarTitleDisplayMode(.large)
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

struct EnterpriseApp: Identifiable {
    let id: String
    let name: String
    let icon: String
    let isConnected: Bool
    let permissions: [String]
}

struct ApplicationRow: View {
    let app: EnterpriseApp
    @StateObject private var serviceStateManager = ServiceStateManager.shared
    
    var body: some View {
        HStack(spacing: 16) {
            // App icon
            Image(systemName: app.icon)
                .font(.system(size: 32))
                .foregroundColor(.blue)
                .frame(width: 48, height: 48)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // App info
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.headline)
                
                Text(app.permissions.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Connection status
            VStack(alignment: .trailing, spacing: 4) {
                if app.isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    
                    Text("Connected")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Button(action: {
                        // Put on hold if service is unavailable
                        let (state, _) = serviceStateManager.getServiceStatus(ServiceStateManager.entraIDService)
                        if state != .connected {
                            serviceStateManager.updateServiceState(
                                app.name,
                                to: .hold,
                                holdInfo: .configurationRequired
                            )
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "link.circle")
                                .foregroundColor(.blue)
                                .font(.title2)
                            
                            Text("Connect")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct ServiceStatusBanner: View {
    @StateObject private var serviceStateManager = ServiceStateManager.shared
    
    var body: some View {
        let (state, holdInfo) = serviceStateManager.getServiceStatus(ServiceStateManager.entraIDService)
        
        if state == .hold, let holdInfo = holdInfo {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    
                    Text("Service On Hold")
                        .font(.headline)
                        .foregroundColor(.orange)
                    
                    Spacer()
                }
                
                Text(holdInfo.reason)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(holdInfo.suggestedAction)
                    .font(.caption)
                    .foregroundColor(.blue)
                
                if holdInfo.canRetry {
                    Button("Retry Connection") {
                        Task {
                            serviceStateManager.updateServiceState(
                                ServiceStateManager.entraIDService,
                                to: .connecting
                            )
                            
                            // Simulate retry
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                serviceStateManager.updateServiceState(
                                    ServiceStateManager.entraIDService,
                                    to: .available
                                )
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
}

#Preview {
    ApplicationsListView()
}