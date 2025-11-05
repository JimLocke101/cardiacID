import SwiftUI
import Combine

struct ActivityEvent: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let eventType: EventType
    let description: String
    let severity: Severity
    
    enum EventType: String, CaseIterable {
        case authentication = "Authentication"
        case device = "Device"
        case security = "Security"
        case system = "System"
    }
    
    enum Severity: String, CaseIterable {
        case info, warning, error, critical
        
        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .yellow
            case .error: return .orange
            case .critical: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            case .critical: return "xmark.shield"
            }
        }
    }
}

class ActivityViewModel: ObservableObject {
    @Published var activityEvents: [ActivityEvent] = []
    @Published var filteredEvents: [ActivityEvent] = []
    @Published var selectedEventTypes: Set<ActivityEvent.EventType> = Set(ActivityEvent.EventType.allCases)
    @Published var selectedSeverity: Set<ActivityEvent.Severity> = Set(ActivityEvent.Severity.allCases)
    @Published var searchText = ""
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadMockData()
        
        // Setup publishers for filtering
        Publishers.CombineLatest3($activityEvents, $selectedEventTypes, $selectedSeverity)
            .combineLatest($searchText)
            .map { combined, searchText in
                let (events, eventTypes, severities) = combined
                return events.filter { event in
                    let matchesType = eventTypes.contains(event.eventType)
                    let matchesSeverity = severities.contains(event.severity)
                    let matchesSearch = searchText.isEmpty || 
                        event.description.localizedCaseInsensitiveContains(searchText) ||
                        event.eventType.rawValue.localizedCaseInsensitiveContains(searchText)
                    
                    return matchesType && matchesSeverity && matchesSearch
                }
            }
            .assign(to: \.filteredEvents, on: self)
            .store(in: &cancellables)
    }
    
    func loadMockData() {
        let now = Date()
        
        let mockEvents: [ActivityEvent] = [
            ActivityEvent(
                timestamp: now.addingTimeInterval(-300),
                eventType: .authentication,
                description: "Successful authentication via cardiac pattern",
                severity: .info
            ),
            ActivityEvent(
                timestamp: now.addingTimeInterval(-600),
                eventType: .device,
                description: "Watch connection established",
                severity: .info
            ),
            ActivityEvent(
                timestamp: now.addingTimeInterval(-3600),
                eventType: .security,
                description: "Failed authentication attempt detected",
                severity: .warning
            ),
            ActivityEvent(
                timestamp: now.addingTimeInterval(-7200),
                eventType: .system,
                description: "App background refresh completed",
                severity: .info
            ),
            ActivityEvent(
                timestamp: now.addingTimeInterval(-86400),
                eventType: .authentication,
                description: "User enrolled new cardiac pattern",
                severity: .info
            ),
            ActivityEvent(
                timestamp: now.addingTimeInterval(-172800),
                eventType: .security,
                description: "Multiple failed authentication attempts detected",
                severity: .error
            ),
        ]
        
        activityEvents = mockEvents
    }
    
    func logEvent(type: ActivityEvent.EventType, description: String, severity: ActivityEvent.Severity) {
        let newEvent = ActivityEvent(
            timestamp: Date(),
            eventType: type,
            description: description,
            severity: severity
        )
        
        activityEvents.insert(newEvent, at: 0)
    }
    
    func clearEvents() {
        activityEvents.removeAll()
    }
}

struct ActivityLogView: View {
    @StateObject private var viewModel = ActivityViewModel()
    @State private var showFilters = false
    
    // Color scheme
    private let colors = HeartIDColors()
    
    var body: some View {
        ZStack {
            colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Search bar
                searchBar
                
                // Filter chips
                filterChips
                
                // Activity list
                activityList
            }
        }
        .navigationTitle("Activity Log")
        .navigationBarItems(
            trailing: Button(action: {
                showFilters.toggle()
            }) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(colors.accent)
            }
        )
        .sheet(isPresented: $showFilters) {
            filterView
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color.gray)
            
            TextField("Search activities", text: $viewModel.searchText)
                .foregroundColor(colors.text)
            
            if !viewModel.searchText.isEmpty {
                Button(action: {
                    viewModel.searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.gray)
                }
            }
        }
        .padding()
        .background(colors.card)
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(ActivityEvent.EventType.allCases, id: \.self) { type in
                    FilterChip(
                        title: type.rawValue,
                        isSelected: viewModel.selectedEventTypes.contains(type),
                        onToggle: {
                            if viewModel.selectedEventTypes.contains(type) {
                                viewModel.selectedEventTypes.remove(type)
                            } else {
                                viewModel.selectedEventTypes.insert(type)
                            }
                        },
                        color: colors.accent
                    )
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
    
    private var activityList: some View {
        List {
            ForEach(viewModel.filteredEvents) { event in
                ActivityEventRow(event: event, colors: colors)
            }
            .listRowBackground(colors.card)
        }
        .listStyle(PlainListStyle())
        .background(colors.background)
    }
    
    private var filterView: some View {
        NavigationView {
            Form {
                Section(header: Text("Event Types")) {
                    ForEach(ActivityEvent.EventType.allCases, id: \.self) { type in
                        Toggle(type.rawValue, isOn: Binding(
                            get: { viewModel.selectedEventTypes.contains(type) },
                            set: { isOn in
                                if isOn {
                                    viewModel.selectedEventTypes.insert(type)
                                } else {
                                    viewModel.selectedEventTypes.remove(type)
                                }
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: colors.accent))
                    }
                }
                
                Section(header: Text("Severity")) {
                    ForEach(ActivityEvent.Severity.allCases, id: \.self) { severity in
                        Toggle(severity.rawValue.capitalized, isOn: Binding(
                            get: { viewModel.selectedSeverity.contains(severity) },
                            set: { isOn in
                                if isOn {
                                    viewModel.selectedSeverity.insert(severity)
                                } else {
                                    viewModel.selectedSeverity.remove(severity)
                                }
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: colors.accent))
                    }
                }
                
                Section {
                    Button("Clear All Filters") {
                        viewModel.selectedEventTypes = Set(ActivityEvent.EventType.allCases)
                        viewModel.selectedSeverity = Set(ActivityEvent.Severity.allCases)
                    }
                    .foregroundColor(colors.accent)
                }
            }
            .navigationTitle("Filter Activities")
            .navigationBarItems(trailing: Button("Done") {
                showFilters = false
            })
            .preferredColorScheme(.dark)
        }
    }
}

struct ActivityEventRow: View {
    let event: ActivityEvent
    let colors: HeartIDColors
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.severity.icon)
                .foregroundColor(event.severity.color)
                .font(.title2)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.eventType.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(colors.accent)
                    
                    Spacer()
                    
                    Text(formattedTime)
                        .font(.caption)
                        .foregroundColor(Color.gray)
                }
                
                Text(event.description)
                    .font(.body)
                    .foregroundColor(colors.text)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var formattedTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: event.timestamp, relativeTo: Date())
    }
}

struct FilterChip: View {
    var title: String
    var isSelected: Bool
    var onToggle: () -> Void
    var color: Color
    
    var body: some View {
        Button(action: onToggle) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? color.opacity(0.2) : Color.gray.opacity(0.1))
                        .overlay(
                            Capsule()
                                .strokeBorder(isSelected ? color : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                )
                .foregroundColor(isSelected ? color : Color.gray)
        }
    }
}

struct ActivityLogView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ActivityLogView()
        }
        .preferredColorScheme(.dark)
    }
}
