//
//  EntraIDTests.swift
//  CardiacIDTests
//
//  Comprehensive tests for EntraID authentication services
//

import Testing
import Foundation
@testable import CardiacID

// MARK: - EntraIDUser Model Tests

struct EntraIDUserTests {

    @Test("EntraIDUser initialization with all fields")
    func testUserInitializationWithAllFields() async throws {
        let user = EntraIDUser(
            id: "user-123",
            displayName: "John Doe",
            email: "john.doe@company.com",
            jobTitle: "Software Engineer",
            department: "Engineering",
            permissions: ["admin", "user"],
            groups: ["Developers", "IT"],
            tenantId: "tenant-123",
            userPrincipalName: "john.doe@company.com"
        )

        #expect(user.id == "user-123")
        #expect(user.displayName == "John Doe")
        #expect(user.email == "john.doe@company.com")
        #expect(user.jobTitle == "Software Engineer")
        #expect(user.department == "Engineering")
        #expect(user.permissions.count == 2)
        #expect(user.groups.count == 2)
        #expect(user.tenantId == "tenant-123")
        #expect(user.userPrincipalName == "john.doe@company.com")
    }

    @Test("EntraIDUser initialization with minimal fields")
    func testUserInitializationWithMinimalFields() async throws {
        let user = EntraIDUser(
            id: "user-456",
            displayName: "Jane Smith",
            email: "jane.smith@company.com"
        )

        #expect(user.id == "user-456")
        #expect(user.displayName == "Jane Smith")
        #expect(user.email == "jane.smith@company.com")
        #expect(user.jobTitle == nil)
        #expect(user.department == nil)
        #expect(user.permissions.isEmpty)
        #expect(user.groups.isEmpty)
        #expect(user.tenantId == nil)
        #expect(user.userPrincipalName == nil)
    }

    @Test("EntraIDUser fullDisplayName with job title")
    func testFullDisplayNameWithJobTitle() async throws {
        let user = EntraIDUser(
            id: "user-123",
            displayName: "John Doe",
            email: "john@company.com",
            jobTitle: "CEO"
        )

        #expect(user.fullDisplayName == "John Doe (CEO)")
    }

    @Test("EntraIDUser fullDisplayName without job title")
    func testFullDisplayNameWithoutJobTitle() async throws {
        let user = EntraIDUser(
            id: "user-123",
            displayName: "John Doe",
            email: "john@company.com"
        )

        #expect(user.fullDisplayName == "John Doe")
    }

    @Test("EntraIDUser hasAdminPermissions detects admin")
    func testHasAdminPermissionsTrue() async throws {
        let user = EntraIDUser(
            id: "user-123",
            displayName: "Admin User",
            email: "admin@company.com",
            permissions: ["user.read", "admin.access", "device.manage"]
        )

        #expect(user.hasAdminPermissions == true)
    }

    @Test("EntraIDUser hasAdminPermissions returns false for non-admin")
    func testHasAdminPermissionsFalse() async throws {
        let user = EntraIDUser(
            id: "user-123",
            displayName: "Regular User",
            email: "user@company.com",
            permissions: ["user.read", "device.view"]
        )

        #expect(user.hasAdminPermissions == false)
    }

    @Test("EntraIDUser hasAdminPermissions case insensitive")
    func testHasAdminPermissionsCaseInsensitive() async throws {
        let user = EntraIDUser(
            id: "user-123",
            displayName: "Admin User",
            email: "admin@company.com",
            permissions: ["ADMIN.ACCESS"]
        )

        #expect(user.hasAdminPermissions == true)
    }

    @Test("EntraIDUser initials calculation single name")
    func testInitialsSingleName() async throws {
        let user = EntraIDUser(
            id: "user-123",
            displayName: "Madonna",
            email: "madonna@company.com"
        )

        #expect(user.initials == "M")
    }

    @Test("EntraIDUser initials calculation two names")
    func testInitialsTwoNames() async throws {
        let user = EntraIDUser(
            id: "user-123",
            displayName: "John Doe",
            email: "john@company.com"
        )

        #expect(user.initials == "JD")
    }

    @Test("EntraIDUser initials calculation three names")
    func testInitialsThreeNames() async throws {
        let user = EntraIDUser(
            id: "user-123",
            displayName: "John Michael Doe",
            email: "john@company.com"
        )

        #expect(user.initials == "JMD")
    }

    @Test("EntraIDUser Codable encoding and decoding")
    func testUserCodable() async throws {
        let original = EntraIDUser(
            id: "user-123",
            displayName: "John Doe",
            email: "john@company.com",
            jobTitle: "Engineer",
            department: "IT",
            permissions: ["read", "write"],
            groups: ["team1"],
            tenantId: "tenant-123",
            userPrincipalName: "john.doe@company.com"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EntraIDUser.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.displayName == original.displayName)
        #expect(decoded.email == original.email)
        #expect(decoded.jobTitle == original.jobTitle)
        #expect(decoded.department == original.department)
        #expect(decoded.permissions == original.permissions)
        #expect(decoded.groups == original.groups)
        #expect(decoded.tenantId == original.tenantId)
        #expect(decoded.userPrincipalName == original.userPrincipalName)
    }
}

// MARK: - EntraIDError Tests

struct EntraIDErrorTests {

    @Test("EntraIDError notConfigured description")
    func testNotConfiguredError() async throws {
        let error = EntraIDError.notConfigured
        #expect(error.errorDescription == "EntraID not configured. Please set tenant ID and client ID.")
    }

    @Test("EntraIDError noViewController description")
    func testNoViewControllerError() async throws {
        let error = EntraIDError.noViewController
        #expect(error.errorDescription == "No view controller available for authentication.")
    }

    @Test("EntraIDError authenticationFailed description")
    func testAuthenticationFailedError() async throws {
        struct TestError: Error, LocalizedError {
            var errorDescription: String? { "Test error" }
        }
        let error = EntraIDError.authenticationFailed(TestError())
        #expect(error.errorDescription?.contains("Authentication failed") == true)
        #expect(error.errorDescription?.contains("Test error") == true)
    }

    @Test("EntraIDError signOutFailed description")
    func testSignOutFailedError() async throws {
        struct TestError: Error, LocalizedError {
            var errorDescription: String? { "Sign out error" }
        }
        let error = EntraIDError.signOutFailed(TestError())
        #expect(error.errorDescription?.contains("Sign out failed") == true)
    }

    @Test("EntraIDError noAccountFound description")
    func testNoAccountFoundError() async throws {
        let error = EntraIDError.noAccountFound
        #expect(error.errorDescription == "No cached account found. Please sign in.")
    }

    @Test("EntraIDError noAccessToken description")
    func testNoAccessTokenError() async throws {
        let error = EntraIDError.noAccessToken
        #expect(error.errorDescription == "No access token available.")
    }

    @Test("EntraIDError tokenRefreshFailed description")
    func testTokenRefreshFailedError() async throws {
        let error = EntraIDError.tokenRefreshFailed
        #expect(error.errorDescription == "Failed to refresh access token.")
    }
}

// MARK: - GraphAPIError Tests

struct GraphAPIErrorTests {

    @Test("GraphAPIError requestFailed description")
    func testRequestFailedError() async throws {
        let error = GraphAPIError.requestFailed
        #expect(error.errorDescription == "Microsoft Graph API request failed")
    }

    @Test("GraphAPIError invalidResponse description")
    func testInvalidResponseError() async throws {
        let error = GraphAPIError.invalidResponse
        #expect(error.errorDescription == "Invalid response from Microsoft Graph API")
    }

    @Test("GraphAPIError decodingError description")
    func testDecodingError() async throws {
        let error = GraphAPIError.decodingError
        #expect(error.errorDescription == "Failed to decode Microsoft Graph API response")
    }
}

// MARK: - Graph Model Tests

struct GraphModelTests {

    @Test("GraphUserProfile decoding")
    func testGraphUserProfileDecoding() async throws {
        let json = """
        {
            "id": "user-123",
            "displayName": "John Doe",
            "mail": "john@company.com",
            "userPrincipalName": "john.doe@company.com",
            "jobTitle": "Engineer",
            "department": "IT"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let profile = try decoder.decode(GraphUserProfile.self, from: data)

        #expect(profile.id == "user-123")
        #expect(profile.displayName == "John Doe")
        #expect(profile.mail == "john@company.com")
        #expect(profile.userPrincipalName == "john.doe@company.com")
        #expect(profile.jobTitle == "Engineer")
        #expect(profile.department == "IT")
    }

    @Test("GraphUserProfile decoding with minimal fields")
    func testGraphUserProfileDecodingMinimal() async throws {
        let json = """
        {
            "id": "user-123",
            "userPrincipalName": "john.doe@company.com"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let profile = try decoder.decode(GraphUserProfile.self, from: data)

        #expect(profile.id == "user-123")
        #expect(profile.displayName == nil)
        #expect(profile.mail == nil)
        #expect(profile.userPrincipalName == "john.doe@company.com")
        #expect(profile.jobTitle == nil)
        #expect(profile.department == nil)
    }

    @Test("GraphApplication decoding")
    func testGraphApplicationDecoding() async throws {
        let json = """
        {
            "id": "app-123",
            "displayName": "My App",
            "appId": "app-id-456",
            "signInAudience": "AzureADMyOrg"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let app = try decoder.decode(GraphApplication.self, from: data)

        #expect(app.id == "app-123")
        #expect(app.displayName == "My App")
        #expect(app.appId == "app-id-456")
        #expect(app.signInAudience == "AzureADMyOrg")
    }

    @Test("GraphGroup decoding")
    func testGraphGroupDecoding() async throws {
        let json = """
        {
            "id": "group-123",
            "displayName": "Developers",
            "description": "Development team",
            "securityEnabled": true
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let group = try decoder.decode(GraphGroup.self, from: data)

        #expect(group.id == "group-123")
        #expect(group.displayName == "Developers")
        #expect(group.description == "Development team")
        #expect(group.securityEnabled == true)
    }

    @Test("GraphDirectoryObject initialization")
    func testGraphDirectoryObject() async throws {
        let obj = GraphDirectoryObject(id: "dir-123")
        #expect(obj.id == "dir-123")
    }
}

// MARK: - EntraIDService Tests (Mock Implementation)

@MainActor
struct EntraIDServiceTests {

    @Test("EntraIDService initialization")
    func testServiceInitialization() async throws {
        let service = EntraIDService()

        #expect(service.isAuthenticated == false)
        #expect(service.currentUser == nil)
        #expect(service.errorMessage == nil)
    }

    @Test("EntraIDService hasPermission returns false when not authenticated")
    func testHasPermissionWhenNotAuthenticated() async throws {
        let service = EntraIDService()

        let hasAccess = service.hasPermission(.doorAccess)
        #expect(hasAccess == false)
    }

    @Test("EntraIDService checkAuthenticationStatus")
    func testCheckAuthenticationStatus() async throws {
        let service = EntraIDService()

        let status = await service.checkAuthenticationStatus()
        #expect(status == false)
    }
}

// MARK: - EntraIDUserModel Tests (from EntraIDService.swift)

struct EntraIDUserModelTests {

    @Test("EntraIDUserModel initialization with all fields")
    func testUserModelInitializationComplete() async throws {
        let user = EntraIDUserModel(
            id: "model-123",
            displayName: "Test User",
            email: "test@company.com",
            jobTitle: "Tester",
            department: "QA",
            permissions: ["test.run"],
            groups: ["QA Team"],
            tenantId: "tenant-456",
            userPrincipalName: "test.user@company.com"
        )

        #expect(user.id == "model-123")
        #expect(user.displayName == "Test User")
        #expect(user.email == "test@company.com")
        #expect(user.jobTitle == "Tester")
        #expect(user.department == "QA")
        #expect(user.permissions == ["test.run"])
        #expect(user.groups == ["QA Team"])
        #expect(user.tenantId == "tenant-456")
        #expect(user.userPrincipalName == "test.user@company.com")
    }

    @Test("EntraIDUserModel initialization with minimal fields")
    func testUserModelInitializationMinimal() async throws {
        let user = EntraIDUserModel(
            id: "model-789",
            displayName: "Minimal User",
            email: "minimal@company.com"
        )

        #expect(user.id == "model-789")
        #expect(user.displayName == "Minimal User")
        #expect(user.email == "minimal@company.com")
        #expect(user.jobTitle == nil)
        #expect(user.department == nil)
        #expect(user.permissions.isEmpty)
        #expect(user.groups.isEmpty)
        #expect(user.tenantId == nil)
        #expect(user.userPrincipalName == nil)
    }

    @Test("EntraIDUserModel Codable encoding and decoding")
    func testUserModelCodable() async throws {
        let original = EntraIDUserModel(
            id: "model-999",
            displayName: "Codable User",
            email: "codable@company.com",
            jobTitle: "Encoder",
            department: "Data",
            permissions: ["encode", "decode"],
            groups: ["Coders"],
            tenantId: "tenant-999",
            userPrincipalName: "codable.user@company.com"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EntraIDUserModel.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.displayName == original.displayName)
        #expect(decoded.email == original.email)
        #expect(decoded.jobTitle == original.jobTitle)
        #expect(decoded.department == original.department)
        #expect(decoded.permissions == original.permissions)
        #expect(decoded.groups == original.groups)
        #expect(decoded.tenantId == original.tenantId)
        #expect(decoded.userPrincipalName == original.userPrincipalName)
    }
}

// MARK: - EntraIDServiceError Tests

struct EntraIDServiceErrorTests {

    @Test("EntraIDServiceError authenticationFailed description")
    func testAuthenticationFailedError() async throws {
        let error = EntraIDServiceError.authenticationFailed("Invalid credentials")
        #expect(error.errorDescription == "Authentication failed: Invalid credentials")
    }

    @Test("EntraIDServiceError notAuthenticated description")
    func testNotAuthenticatedError() async throws {
        let error = EntraIDServiceError.notAuthenticated
        #expect(error.errorDescription == "User is not authenticated")
    }

    @Test("EntraIDServiceError tokenRefreshFailed description")
    func testTokenRefreshFailedError() async throws {
        let error = EntraIDServiceError.tokenRefreshFailed
        #expect(error.errorDescription == "Failed to refresh token")
    }

    @Test("EntraIDServiceError networkError description")
    func testNetworkError() async throws {
        let error = EntraIDServiceError.networkError
        #expect(error.errorDescription == "Network error occurred")
    }

    @Test("EntraIDServiceError unknown description")
    func testUnknownError() async throws {
        struct CustomError: Error, LocalizedError {
            var errorDescription: String? { "Custom error message" }
        }

        let error = EntraIDServiceError.unknown(CustomError())
        #expect(error.errorDescription?.contains("Unknown error") == true)
        #expect(error.errorDescription?.contains("Custom error message") == true)
    }
}

// MARK: - EntraIDServicePermission Tests

struct EntraIDServicePermissionTests {

    @Test("EntraIDServicePermission all cases exist")
    func testAllPermissionCases() async throws {
        let permissions = EntraIDServicePermission.allCases

        #expect(permissions.count == 5)
        #expect(permissions.contains(.doorAccess))
        #expect(permissions.contains(.nfcAccess))
        #expect(permissions.contains(.bluetoothAccess))
        #expect(permissions.contains(.heartAuthentication))
        #expect(permissions.contains(.deviceManagement))
    }

    @Test("EntraIDServicePermission raw values")
    func testPermissionRawValues() async throws {
        #expect(EntraIDServicePermission.doorAccess.rawValue == "door.access")
        #expect(EntraIDServicePermission.nfcAccess.rawValue == "nfc.access")
        #expect(EntraIDServicePermission.bluetoothAccess.rawValue == "bluetooth.access")
        #expect(EntraIDServicePermission.heartAuthentication.rawValue == "heart.authentication")
        #expect(EntraIDServicePermission.deviceManagement.rawValue == "device.management")
    }

    @Test("EntraIDServicePermission initialization from raw value")
    func testPermissionFromRawValue() async throws {
        let doorAccess = EntraIDServicePermission(rawValue: "door.access")
        #expect(doorAccess == .doorAccess)

        let nfcAccess = EntraIDServicePermission(rawValue: "nfc.access")
        #expect(nfcAccess == .nfcAccess)

        let invalid = EntraIDServicePermission(rawValue: "invalid.permission")
        #expect(invalid == nil)
    }
}

// MARK: - EntraIDServiceFactory Tests

@MainActor
struct EntraIDServiceFactoryTests {

    @Test("EntraIDServiceFactory create returns service")
    func testFactoryCreate() async throws {
        let service = EntraIDServiceFactory.create()
        #expect(service.isAuthenticated == false)
    }

    @Test("EntraIDServiceFactory createMock returns service")
    func testFactoryCreateMock() async throws {
        let service = EntraIDServiceFactory.createMock()
        #expect(service.isAuthenticated == false)
    }

    @Test("EntraIDServiceFactory createReal returns service")
    func testFactoryCreateReal() async throws {
        let service = EntraIDServiceFactory.createReal()
        #expect(service.isAuthenticated == false)
    }
}
