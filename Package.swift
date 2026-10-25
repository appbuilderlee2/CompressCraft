// swift-tools-version: 5.7
import PackageDescription
let package = Package(name: "CompressCraft", platforms: [.macOS(.v12)], products: [.executable(name: "CompressCraft", targets: ["CompressCraft"])], targets: [.executableTarget(name: "CompressCraft", path: "Sources/CompressCraft")])
