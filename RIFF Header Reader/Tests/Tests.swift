import Foundation
import Testing
@testable import RIFFHeaderReader

let resources = Bundle.module.url(forResource: "Resources", withExtension: nil)!

@Test func example() async throws {
   let data = try Data(contentsOf: resources.appendingPathComponent("2_webp_ll.webp"))
   let summary = try RIFFHeaderReader.describe(data)
   print(summary)
}
