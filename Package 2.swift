// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CardiacID",
    platforms: [
        .iOS(.v16),
        .watchOS(.v9),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CardiacID",
            targets: ["CardiacID"]
        ),
    ],
    dependencies: [
        // Microsoft Authentication Library - iOS/macOS only
        .package(
            url: "https://github.com/AzureAD/microsoft-authentication-library-for-objc",
            from: "1.3.0"
        ),
        // Other dependencies that support all platforms
        .package(
            url: "https://github.com/supabase/supabase-swift.git",
            from: "2.0.0"
        )
    ],
    targets: [
        .target(
            name: "CardiacID",
            dependencies: [
                // Conditionally include MSAL only for supported platforms
                .product(
                    name: "MSAL", 
                    package: "microsoft-authentication-library-for-objc",
                    condition: .when(platforms: [.iOS, .macOS])
                ),
                .product(name: "Supabase", package: "supabase-swift")
            ]
        ),
        .testTarget(
            name: "CardiacIDTests",
            dependencies: ["CardiacID"]
        ),
    ]
)