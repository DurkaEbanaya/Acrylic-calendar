// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FluentCalendar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FluentCalendar", targets: ["FluentCalendar"])
    ],
    targets: [
        .executableTarget(
            name: "FluentCalendar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
