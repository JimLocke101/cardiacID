import Foundation

struct User: Identifiable, Codable, Equatable {
    let id: String
    let email: String
    var firstName: String?
    var lastName: String?
    var profileImageUrl: String?
    var deviceIds: [String]?
    var enrollmentStatus: EnrollmentStatus
    var createdAt: Date
    
    enum EnrollmentStatus: String, Codable {
        case notStarted = "not_started"
        case inProgress = "in_progress"
        case completed = "completed"
    }
    
    // Computed properties
    var fullName: String {
        if let firstName = firstName, let lastName = lastName {
            return "\(firstName) \(lastName)"
        } else if let firstName = firstName {
            return firstName
        } else if let lastName = lastName {
            return lastName
        } else {
            return email
        }
    }
    
    var displayName: String {
        return fullName
    }
    
    var initials: String {
        if let firstName = firstName?.first, let lastName = lastName?.first {
            return "\(firstName)\(lastName)"
        } else if let firstName = firstName?.first {
            return String(firstName)
        } else if let lastName = lastName?.first {
            return String(lastName)
        } else if let firstChar = email.first {
            return String(firstChar).uppercased()
        } else {
            return "U"
        }
    }
    
    // Simplified initializers to help with compatibility
    init(id: String, email: String, firstName: String? = nil, lastName: String? = nil, profileImageUrl: String? = nil, deviceIds: [String]? = nil, enrollmentStatus: EnrollmentStatus = .notStarted, createdAt: Date = Date()) {
        self.id = id
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.profileImageUrl = profileImageUrl
        self.deviceIds = deviceIds
        self.enrollmentStatus = enrollmentStatus
        self.createdAt = createdAt
    }
}
