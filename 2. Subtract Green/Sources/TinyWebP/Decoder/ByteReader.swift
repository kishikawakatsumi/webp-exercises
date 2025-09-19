import Foundation

struct ByteReader {
  private let data: Data
  private(set) var offset: Data.Index = 0

  init(_ data: Data) {
    self.data = data
  }

  mutating func read() throws -> UInt8? {
    guard offset < data.endIndex else {
      return nil
    }
    defer {
      offset = data.index(after: offset)
    }

    return data[offset]
  }

  mutating func read(_ count: Int) throws -> [UInt8] {
    guard offset + count <= data.endIndex else {
      throw NSError(domain: "ByteReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not enough bytes to read"])
    }

    let bytes = data[offset..<data.index(offset, offsetBy: count)]
    offset = data.index(offset, offsetBy: count)

    return Array(bytes)
  }

  mutating func skip(_ count: Int) throws {
    guard offset + count <= data.endIndex else {
      throw NSError(domain: "ByteReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not enough bytes to skip"])
    }
    
    offset = data.index(offset, offsetBy: count)
  }
}
