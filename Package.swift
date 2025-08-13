// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "mom-bridge",
  // You can omit platforms when building on Linux; leaving macOS is fine too.
  products: [
    .executable(name: "mom-bridge", targets: ["App"])
  ],
  dependencies: [
    .package(url: "https://github.com/vapor/vapor.git", from: "4.92.0"),
    .package(url: "https://github.com/PADL/MOM.git", branch: "main")
  ],
  targets: [
    .executableTarget(
      name: "App",
      dependencies: [
        .product(name: "Vapor", package: "vapor"),
        .product(name: "Surrogate", package: "MOM")
      ],
      path: "Sources/App"
    )
  ]
)