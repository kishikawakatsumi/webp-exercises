// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TinyWebP",
  products: [
    .library(
      name: "TinyWebP",
      targets: [
        "TinyWebP"
      ]
    ),
  ],
  targets: [
    .target(
      name: "TinyWebP"),
    .testTarget(
      name: "TinyWebPTests",
      dependencies: [
        "TinyWebP"
      ],
      resources: [
        .copy("Resources")
      ]
    ),
  ]
)
