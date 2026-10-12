// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Grab",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", exact: "2.55.3")
    ],
    targets: [
        .executableTarget(
            name: "Grab",
            dependencies: [.product(name: "Supabase", package: "supabase-swift")],
            path: "Sources/Grab",
            exclude: ["Resources"]
        )
    ]
)
