import Foundation

struct FourCC: Equatable {
  private let c0, c1, c2, c3: UInt8
  private var string: String {
    String(decoding: [c0, c1, c2, c3], as: UTF8.self)
  }

  init(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) {
    (c0, c1, c2, c3) = (a, b, c, d)
  }

  init(_ s: StaticString) {
    precondition(s.utf8CodeUnitCount == 4)
    self.init(s.utf8Start[0], s.utf8Start[1], s.utf8Start[2], s.utf8Start[3])
  }
}

enum RIFFError: Error {
  case missingPaddingByte
  case missingRIFFChunkHeader
  case listSubchunkTooLong
  case shortChunkData
  case shortChunkHeader
  case staleReader
}

struct EOFError: Error {}
