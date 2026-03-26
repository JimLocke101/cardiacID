// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

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
        // HeartIDCore — local package: platform-agnostic models, engines, and protocols
        .package(path: "HeartIDCore"),
        // Supabase Swift SDK
        .package(
            url: "https://github.com/supabase/supabase-swift.git",
            from: "2.37.0"
        ),
        // Microsoft Authentication Library (MSAL)
        .package(
            url: "https://github.com/AzureAD/microsoft-authentication-library-for-objc.git",
            from: "2.5.1"
        ),
    ],
    targets: [
        .target(
            name: "CardiacID",
            dependencies: [
                .product(name: "HeartIDCore", package: "HeartIDCore"),
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "Auth", package: "supabase-swift"),
                .product(name: "Realtime", package: "supabase-swift"),
                .product(name: "Storage", package: "supabase-swift"),
                .product(name: "PostgREST", package: "supabase-swift"),
                .product(name: "MSAL", package: "microsoft-authentication-library-for-objc"),
            ]
        ),
    ]
)
