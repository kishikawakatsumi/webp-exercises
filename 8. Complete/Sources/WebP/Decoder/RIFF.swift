import Foundation

struct FourCC: Equatable {
  let bytes: [UInt8]

  init(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) {
    bytes = [b0, b1, b2, b3]
  }

  init(_ str: String) {
    let chars = Array(str.utf8)
    precondition(chars.count == 4)
    bytes = [chars[0], chars[1], chars[2], chars[3]]
  }

  static let alph = FourCC("ALPH")
  static let vp8 = FourCC("VP8 ")
  static let vp8l = FourCC("VP8L")
  static let vp8x = FourCC("VP8X")
  static let webp = FourCC("WEBP")
  static let list = FourCC("LIST")
  static let riff = FourCC("RIFF")
}

enum WebPError: Error {
  case invalidFormat
  case invalidCodeLengths
  case invalidHuffmanTree
  case shortChunkData
  case shortChunkHeader
  case staleReader
  case missingPaddingByte
  case missingRIFFChunkHeader
  case listSubchunkTooLong
  case unexpectedEOF
  case invalidColorCacheParameters
  case invalidLZ77Parameters
  case invalidColorCacheIndex
  case invalidTransform
  case invalidVersion
  case invalidHeader
}

struct EOFError: Error {}
