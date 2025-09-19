import Foundation
import CoreGraphics
import Testing
@testable import TinyWebP

let resources = Bundle.module.url(forResource: "Resources", withExtension: nil)!

@Test
func encode16x16() async throws {
  let cgImage = CGImage(
    pngDataProviderSource: CGDataProvider(
      url: resources.appendingPathComponent("16x16.png") as CFURL
    )!,
    decode: nil,
    shouldInterpolate: false,
    intent: .defaultIntent
  )!

  let data = try WebPEncoder.encode(image: cgImage)
  let expected = try Data(contentsOf: resources.appendingPathComponent("16x16ColorIndexing.webp"))

  #expect(data == expected)
}

//@Test
//func decode16x16() async throws {
//  let data = try Data(
//    contentsOf: resources.appendingPathComponent("16x16ColorIndexing.webp")
//  )
//
//  let image = try WebPDecoder.decode(data)
//  let cgImage = try #require(image.makeCGImage())
//
//  let expected = try WebPEncoder.encode(image: cgImage)
//  #expect(data == expected)
//}
