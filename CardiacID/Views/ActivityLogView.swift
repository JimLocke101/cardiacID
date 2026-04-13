// ActivityLogView.swift
// CardiacID
//
// Real-time activity log backed by:
//   1. Supabase auth_events table (persistent, fetched on load + pull-to-refresh)
//   2. AuditLogger in-memory buffer (local policy decisions, instant)
// No mock data — every row represents a real event.

import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
class ActivityViewModel: ObservableObject {
    @Published var events: [ActivityEvent] = []
    @Published var filteredEvents: [ActivityEvent] = []
    @Published var selectedTypes: Set<ActivityEvent.EventType> = Set(ActivityEvent.EventType.allCases)
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let supabaseClient = AppSupabaseClientLocal.shared
    private let auditLogger    = AuditLogger.shared
    private var cancellables   = Set<AnyCancellable>()

    init() {
        // Reactive filter pipeline
        Publishers.CombineLatest3($events, $selectedTypes, $searchText)
            .map { events, types, search in
                events.filter { e in
                    let matchType   = types.contains(e.eventType)
                    let matchSearch = search.isEmpty
                        || e.description.localizedCaseInsensitiveContains(search)
                        || e.eventType.rawValue.localizedCaseInsensitiveContains(search)
                    return matchType && matchSearch
                }
            }
            .assign(to: \.filteredEvents, on: self)
            .store(in: &cancellables)
    }

    func loadEvents() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var combined: [ActivityEvent] = []

        // 1. Supabase auth_events (persistent cloud — only works when signed in)
        do {
            let dbEvents = try await supabaseClient.getRecentAuthEvents(limit: 50)
            combined.append(contentsOf: dbEvents.compactMap { mapAuthEvent($0) })
        } catch {
            // Non-fatal — cloud events unavailable (demo mode or not signed in)
        }

        // 2. AuditLogger: formal SecurityEvent records (HeartID policy decisions)
        let policyEvents = auditLogger.recentSecurityEvents()
        for se in policyEvents {
            combined.append(ActivityEvent(
                timestamp: se.timestamp,
                eventType: mapSecurityEventType(se.action),
                description: "\(se.action.displayName) — \(se.decision.rawValue)",
                severity: se.decision == .deny ? .warning : .info,
                source: .local
            ))
        }

        // 3. AuditLogger: operational entries (sign-in attempts, Watch state, etc.)
        //    This is where AuthViewModel, WatchConnectivity, and other services log.
        let operationalEvents = auditLogger.recentOperationalEntries()
        for op in operationalEvents {
            combined.append(ActivityEvent(
                timestamp: op.timestamp,
                eventType: mapOperationalEventType(op.action),
                description: formatOperationalDescription(action: op.action, outcome: op.outcome, reason: op.reasonCode),
                severity: mapOperationalSeverity(outcome: op.outcome),
                source: .local
            ))
        }

        // Deduplicate by timestamp proximity (within 1 second + same description = same event)
        var deduped: [ActivityEvent] = []
        let sorted = combined.sorted { $0.timestamp > $1.timestamp }
        for event in sorted {
            if !deduped.contains(where: { abs($0.timestamp.timeIntervalSince(event.timestamp)) < 1 && $0.description == event.description }) {
                deduped.append(event)
            }
        }

        events = deduped
    }

    // MARK: - Operational event mapping

    private func mapOperationalEventType(_ action: String) -> ActivityEvent.EventType {
        if action.hasPrefix("sign_in") || action.hasPrefix("sign_out") || action.hasPrefix("demo_mode") || action.hasPrefix("registration") {
            return .authentication
        }
        if action.hasPrefix("watch.") {
            return .device
        }
        if action.hasPrefix("policy.") || action.hasPrefix("session.") || action.hasPrefix("vault.") || action.hasPrefix("hardware.") {
            return .security
        }
        if action.hasPrefix("HeartID") || action.hasPrefix("passkey.") || action.hasPrefix("verify-heart") {
            return .biometric
        }
        return .system
    }

    private func formatOperationalDescription(action: String, outcome: String, reason: String?) -> String {
        switch action {
        case "sign_in_attempt":     return "Sign-in attempted" + (reason.map { " (\($0))" } ?? "")
        case "sign_in_success":     return "Sign-in successful" + (reason.map { " — \($0)" } ?? "")
        case "sign_in_failed":      return "Sign-in failed: \(reason ?? outcome)"
        case "registration_attempt": return "Registration attempted"
        case "registration_success": return "Registration successful"
        case "registration_failed":  return "Registration failed: \(reason ?? outcome)"
        case "sign_out":            return "User signed out"
        case "sign_out_complete":   return "Sign-out completed"
        case "demo_mode_attempt":   return "Demo mode requested"
        case "demo_mode_activated": return "Demo mode activated"
        case "profile_updated":     return "Profile updated"
        case "watch.session_activated":   return "Watch connected — \(reason ?? "")"
        case "watch.activation_error":    return "Watch connection error: \(reason ?? "unknown")"
        case "watch.became_reachable":    return "Watch became reachable"
        case "watch.became_unreachable":  return "Watch connection lost"
        case "watch.state_changed":       return "Watch state changed — \(outcome)"
        case "watch.session_inactive":    return "Watch session became inactive"
        case "watch.session_deactivated": return "Watch session deactivated"
        default:
            let display = action.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " ")
            return "\(display.capitalized) — \(outcome)" + (reason.map { " (\($0))" } ?? "")
        }
    }

    private func mapOperationalSeverity(outcome: String) -> ActivityEvent.Severity {
        switch outcome.lowercased() {
        case "success", "ok", "connected", "success":   return .info
        case "failed", "error", "denied":                return .error
        case "disconnected", "inactive", "deactivated":  return .warning
        default:                                         return .info
        }
    }

    func clearEvents() async {
        // Clear local audit log
        auditLogger.clear()
        events.removeAll()
    }

    // MARK: - Mapping helpers

    private func mapAuthEvent(_ event: AuthEvent) -> ActivityEvent? {
        let type: ActivityEvent.EventType
        let severity: ActivityEvent.Severity

        switch event.eventType {
        case .signIn, .passwordAuth, .authentication:
            type = .authentication
            severity = event.success ? .info : .warning
        case .signOut:
            type = .authentication
            severity = .info
        case .biometricAuth:
            type = .biometric
            severity = event.success ? .info : .warning
        case .failedAttempt, .accountLocked:
            type = .security
            severity = event.success ? .warning : .error
        case .enrollment:
            type = .biometric
            severity = .info
        case .revocation:
            type = .security
            severity = .critical
        case .tokenRefresh:
            type = .system
            severity = .info
        case .passwordReset:
            type = .authentication
            severity = .info
        }

        return ActivityEvent(
            timestamp: event.timestamp,
            eventType: type,
            description: formatEventDescription(event),
            severity: severity,
            source: .cloud
        )
    }

    private func formatEventDescription(_ event: AuthEvent) -> String {
        let method = event.metadata?["method"] ?? event.eventType.rawValue
        let status = event.success ? "Success" : "Failed"
        switch event.eventType {
        case .signIn:      return "\(status) sign-in via \(method)"
        case .signOut:     return "User signed out"
        case .biometricAuth: return "\(status) cardiac biometric verification"
        case .failedAttempt: return "Failed authentication attempt"
        case .enrollment:  return "Cardiac pattern enrolled"
        case .revocation:  return "Credential revoked"
        case .tokenRefresh: return "Session token refreshed"
        case .accountLocked: return "Account locked after failed attempts"
        case .passwordAuth: return "\(status) password authentication"
        case .passwordReset: return "Password reset requested"
        case .authentication: return "\(status) authentication — \(method)"
        }
    }

    private func mapSecurityEventType(_ action: ProtectedAction) -> ActivityEvent.EventType {
        switch action {
        case .unlockProtectedFile:      return .security
        case .signInToApp:              return .authentication
        case .authorizeSensitiveAction: return .security
        case .authorizeHardwareCommand: return .device
        case .beginPasskeyRegistration: return .authentication
        case .beginPasskeyAssertion:    return .authentication
        }
    }
}

// MARK: - Activity Event Model

struct ActivityEvent: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let eventType: EventType
    let description: String
    let severity: Severity
    let source: Source

    enum Source: String { case cloud, local }

    enum EventType: String, CaseIterable {
        case authentication = "Authentication"
        case biometric      = "Biometric"
        case device         = "Device"
        case security       = "Security"
        case system         = "System"

        var icon: String {
            switch self {
            case .authentication: return "person.badge.key.fill"
            case .biometric:      return "waveform.path.ecg"
            case .device:         return "applewatch"
            case .security:       return "lock.shield.fill"
            case .system:         return "gearshape.fill"
            }
        }
    }

    enum Severity: String, CaseIterable {
        case info, warning, error, critical

        var color: Color {
            switch self {
            case .info:     return .blue
            case .warning:  return .yellow
            case .error:    return .orange
            case .critical: return .red
            }
        }

        var icon: String {
            switch self {
            case .info:     return "info.circle.fill"
            case .warning:  return "exclamationmark.triangle.fill"
            case .error:    return "xmark.octagon.fill"
            case .critical: return "xmark.shield.fill"
            }
        }
    }
}

// MARK: - View

struct ActivityLogView: View {
    @StateObject private var viewModel = ActivityViewModel()
    @State private var showFilters = false

    private let colors = HeartIDColors()

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                searchBar
                filterChips
                activityList
            }
        }
        .navigationTitle("Activity Log")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showFilters.toggle() }) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(colors.accent)
                }
            }
        }
        .sheet(isPresented: $showFilters) { filterView }
        .task { await viewModel.loadEvents() }
        .refreshable { await viewModel.loadEvents() }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.gray)
            TextField("Search activity", text: $viewModel.searchText)
                .foregroundColor(colors.text)
            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(colors.card)
        .cornerRadius(10)
        .padding(.horizontal)
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityEvent.EventType.allCases, id: \.self) { type in
                    FilterChip(
                        title: type.rawValue,
                        isSelected: viewModel.selectedTypes.contains(type),
                        onToggle: {
                            if viewModel.selectedTypes.contains(type) { viewModel.selectedTypes.remove(type) }
                            else { viewModel.selectedTypes.insert(type) }
                        },
                        color: colors.accent
                    )
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    // MARK: - List

    private var activityList: some View {
        Group {
            if viewModel.isLoading && viewModel.events.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Text("Loading activity…").font(.caption).foregroundColor(colors.secondary)
                    Spacer()
                }
            } else if viewModel.filteredEvents.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray").font(.system(size: 40)).foregroundColor(colors.secondary)
                    Text("No activity yet").font(.headline).foregroundColor(colors.secondary)
                    Text("Authentication events will appear here in real time.")
                        .font(.caption).foregroundColor(colors.secondary).multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    ForEach(viewModel.filteredEvents) { event in
                        ActivityEventRow(event: event, colors: colors)
                    }
                    .listRowBackground(colors.card)

                    if let err = viewModel.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                            Text(err).font(.caption).foregroundColor(.orange)
                        }
                        .listRowBackground(colors.card)
                    }
                }
                .listStyle(.plain)
                .background(colors.background)
            }
        }
    }

    // MARK: - Filter sheet

    private var filterView: some View {
        NavigationView {
            Form {
                Section("Event Types") {
                    ForEach(ActivityEvent.EventType.allCases, id: \.self) { type in
                        Toggle(type.rawValue, isOn: Binding(
                            get: { viewModel.selectedTypes.contains(type) },
                            set: { if $0 { viewModel.selectedTypes.insert(type) } else { viewModel.selectedTypes.remove(type) } }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: colors.accent))
                    }
                }
                Section {
                    Button("Show All") {
                        viewModel.selectedTypes = Set(ActivityEvent.EventType.allCases)
                    }
                    .foregroundColor(colors.accent)
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showFilters = false }
                }
            }
        }
    }
}

// MARK: - Row

struct ActivityEventRow: View {
    let event: ActivityEvent
    let colors: HeartIDColors

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.severity.icon)
                .foregroundColor(event.severity.color)
                .font(.title3)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(event.eventType.rawValue, systemImage: event.eventType.icon)
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(colors.accent)
                    Spacer()
                    Text(event.source == .cloud ? "" : "local")
                        .font(.caption2).foregroundColor(colors.secondary)
                    Text(relativeTime)
                        .font(.caption).foregroundColor(.gray)
                }

                Text(event.description)
                    .font(.subheadline).foregroundColor(colors.text)
            }
        }
        .padding(.vertical, 6)
    }

    private var relativeTime: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: event.timestamp, relativeTo: Date())
    }
}

// MARK: - Filter Chip (reused)

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let onToggle: () -> Void
    let color: Color

    var body: some View {
        Button(action: onToggle) {
            Text(title)
                .font(.caption).fontWeight(.medium)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(isSelected ? color.opacity(0.2) : Color.gray.opacity(0.1))
                    .overlay(Capsule().strokeBorder(isSelected ? color : Color.gray.opacity(0.3), lineWidth: 1)))
                .foregroundColor(isSelected ? color : .gray)
        }
    }
}
