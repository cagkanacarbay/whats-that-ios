// swift-tools-version: 5.10

import Foundation
import PackageDescription

let useRemoteDependencies = ProcessInfo.processInfo.environment["USE_REMOTE_DEPS"] != "0"

let thirdPartyDependencies: [Package.Dependency] = [
    .package(
        url: "https://github.com/supabase-community/supabase-swift.git",
        from: "2.34.0"
    ),
    .package(
        url: "https://github.com/google/GoogleSignIn-iOS.git",
        from: "7.1.0"
    ),
    .package(
        url: "https://github.com/kean/Nuke.git",
        from: "12.8.0"
    ),
    .package(
        url: "https://github.com/gonzalezreal/MarkdownUI.git",
        from: "2.4.1"
    ),
    .package(
        url: "https://github.com/apple/swift-collections.git",
        from: "1.3.0"
    ),
    .package(
        url: "https://github.com/apple/swift-algorithms.git",
        from: "1.2.1"
    )
]

var infrastructureDependencies: [Target.Dependency] = [
    "WhatsThatShared",
    "WhatsThatDomain"
]
var dataDependencies: [Target.Dependency] = [
    "WhatsThatDomain",
    "WhatsThatInfrastructure",
    "WhatsThatShared"
]
var presentationDependencies: [Target.Dependency] = [
    "WhatsThatDomain",
    "WhatsThatShared"
]
var appDependencies: [Target.Dependency] = [
    "WhatsThatPresentation",
    "WhatsThatData",
    "WhatsThatInfrastructure",
    "WhatsThatDomain",
    "WhatsThatShared"
]
var sharedDependencies: [Target.Dependency] = []

var packageDependencies: [Package.Dependency] = []
var targetSwiftSettings: [SwiftSetting] = []

if useRemoteDependencies {
    packageDependencies = thirdPartyDependencies
    infrastructureDependencies += [
        .product(name: "Supabase", package: "supabase-swift"),
        .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
        .product(name: "GoogleSignInSwift", package: "GoogleSignIn-iOS"),
        .product(name: "Collections", package: "swift-collections"),
        .product(name: "Algorithms", package: "swift-algorithms")
    ]
    dataDependencies += [
        .product(name: "Supabase", package: "supabase-swift")
    ]
    presentationDependencies += [
        .product(name: "MarkdownUI", package: "MarkdownUI"),
        .product(name: "NukeUI", package: "Nuke"),
        .product(name: "Nuke", package: "Nuke")
    ]
    appDependencies += [
        .product(name: "MarkdownUI", package: "MarkdownUI")
    ]
    sharedDependencies += [
        .product(name: "MarkdownUI", package: "MarkdownUI")
    ]

    targetSwiftSettings.append(.define("USE_REMOTE_DEPS"))
}

var package = Package(
    name: "WhatsThatKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "WhatsThatApp", targets: ["WhatsThatApp"]),
        .library(name: "WhatsThatPresentation", targets: ["WhatsThatPresentation"]),
        .library(name: "WhatsThatDomain", targets: ["WhatsThatDomain"]),
        .library(name: "WhatsThatData", targets: ["WhatsThatData"]),
        .library(name: "WhatsThatInfrastructure", targets: ["WhatsThatInfrastructure"]),
        .library(name: "WhatsThatShared", targets: ["WhatsThatShared"]),
        // Temporary compatibility product so the Xcode app target can keep linking the legacy name.
        .library(name: "WhatsThatIOSFeature", targets: ["WhatsThatApp"])
    ],
    dependencies: packageDependencies,
    targets: [
        .target(
            name: "WhatsThatShared",
            dependencies: sharedDependencies,
            path: "Sources/WhatsThatShared",
            swiftSettings: targetSwiftSettings
        ),
        .target(
            name: "WhatsThatDomain",
            dependencies: [
                "WhatsThatShared"
            ],
            path: "Sources/WhatsThatDomain",
            swiftSettings: targetSwiftSettings
        ),
        .target(
            name: "WhatsThatInfrastructure",
            dependencies: infrastructureDependencies,
            path: "Sources/WhatsThatInfrastructure",
            swiftSettings: targetSwiftSettings
        ),
        .target(
            name: "WhatsThatData",
            dependencies: dataDependencies,
            path: "Sources/WhatsThatData",
            swiftSettings: targetSwiftSettings
        ),
        .target(
            name: "WhatsThatPresentation",
            dependencies: presentationDependencies,
            path: "Sources/WhatsThatPresentation",
            swiftSettings: targetSwiftSettings
        ),
        .target(
            name: "WhatsThatApp",
            dependencies: appDependencies,
            path: "Sources/WhatsThatApp",
            swiftSettings: targetSwiftSettings
        ),
        .testTarget(
            name: "WhatsThatDomainTests",
            dependencies: [
                "WhatsThatDomain",
                "WhatsThatData"
            ],
            path: "Tests/WhatsThatDomainTests",
            swiftSettings: targetSwiftSettings
        ),
        .testTarget(
            name: "WhatsThatDataTests",
            dependencies: [
                "WhatsThatData"
            ],
            path: "Tests/WhatsThatDataTests",
            swiftSettings: targetSwiftSettings
        ),
        .testTarget(
            name: "WhatsThatInfrastructureTests",
            dependencies: [
                "WhatsThatInfrastructure"
            ],
            path: "Tests/WhatsThatInfrastructureTests",
            swiftSettings: targetSwiftSettings
        ),
        .testTarget(
            name: "WhatsThatPresentationTests",
            dependencies: [
                "WhatsThatPresentation",
                "WhatsThatData"
            ],
            path: "Tests/WhatsThatPresentationTests",
            swiftSettings: targetSwiftSettings
        ),
        .testTarget(
            name: "WhatsThatAppTests",
            dependencies: [
                "WhatsThatApp"
            ],
            path: "Tests/WhatsThatAppTests",
            swiftSettings: targetSwiftSettings
        ),
        .testTarget(
            name: "WhatsThatSharedTests",
            dependencies: [
                "WhatsThatShared"
            ],
            path: "Tests/WhatsThatSharedTests",
            swiftSettings: targetSwiftSettings
        )
    ],
    swiftLanguageVersions: [.v5]
)
