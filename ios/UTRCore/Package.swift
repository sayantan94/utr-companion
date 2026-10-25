// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "UTRCore", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "UTRCore", targets: ["UTRCore"])], targets: [.target(name: "UTRCore"), .testTarget(name: "UTRCoreTests", dependencies: ["UTRCore"])])
