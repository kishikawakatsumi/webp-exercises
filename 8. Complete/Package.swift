// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "WebP",
  products: [
    .library(
      name: "WebP",
      targets: [
        "WebP"
      ]
    ),
  ],
  targets: [
    .target(
      name: "WebP"
    ),
    .testTarget(
      name: "Tests",
      dependencies: [
        "WebP"
      ],
      resources: [
        .copy("Resources")
      ]
    ),
  ]
)
