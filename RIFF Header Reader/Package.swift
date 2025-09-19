// swift-tools-version: 6.0
import PackageDescription
let package = Package(
  name: "RIFFHeaderReader",
  products: [
    .library(
      name: "RIFFHeaderReader",
      targets: ["RIFFHeaderReader"]
    ),
  ],
  targets: [
    .target(
      name: "RIFFHeaderReader"),
    .testTarget(
      name: "RIFFHeaderReaderTests",
      dependencies: ["RIFFHeaderReader"],
      resources: [
        .copy("Resources")
      ]
    )
  ]
)
