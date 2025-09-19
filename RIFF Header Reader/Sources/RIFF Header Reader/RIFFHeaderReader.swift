import Foundation

struct RIFFHeaderReader {
  static func parse(_ data: Data) throws -> (header: RIFFHeader, chunks: [RIFFChunk]) {
    var reader = ByteReader(data)

    let sigunature = try reader.readFourCC()
    guard sigunature == "RIFF" else { throw WebPListError.invalidSignature(sigunature) }

    let riffSize = try reader.readUInt32()
    let formType = try reader.readFourCC()
    guard formType == "WEBP" else { throw WebPListError.notWEBP(formType) }

    let logicalEnd = 8 + Int(riffSize)
    guard logicalEnd <= data.count else { throw WebPListError.truncatedRIFF }

    var chunks: [RIFFChunk] = []

    while reader.offset + 8 <= logicalEnd {
      let fourCC = try reader.readFourCC()
      let size = try reader.readUInt32()
      let payloadStart = reader.offset
      let payloadEnd = payloadStart + Int(size)

      guard payloadEnd <= logicalEnd else {
        throw WebPListError.chunkOutOfRange(fourCC: fourCC)
      }

      chunks.append(.init(fourCC: fourCC, sizeLE: size, dataStartOffset: payloadStart))

      try reader.skip(Int(size))
      if (size & 1) == 1 {
        guard reader.offset + 1 <= logicalEnd else {
          throw WebPListError.chunkOutOfRange(fourCC: fourCC)
        }
        try reader.skip(1)
      }
    }

    let header = RIFFHeader(signature: sigunature, fileSizeLE: riffSize, formType: formType)
    return (header, chunks)
  }

  static func describe(_ data: Data) throws -> String {
    let (h, chunks) = try parse(data)
    var parts: [String] = []
    parts.append("\(h.signature)")
    parts.append("\(h.fileSizeLE) bytes")
    parts.append("\(h.formType)")
    for c in chunks {
      parts.append("\(c.fourCC)")
      parts.append("\(c.sizeLE) bytes")
    }
    return parts.joined(separator: ", ")
  }
}

enum ByteReaderError: Error { case endOfData, invalidString }

struct ByteReader {
  private let data: Data
  private(set) var offset: Data.Index = 0

  init(_ data: Data) { self.data = data }

  mutating func read() throws -> UInt8 {
    guard offset < data.endIndex else { throw ByteReaderError.endOfData }
    defer { offset = data.index(after: offset) }
    return data[offset]
  }

  mutating func read(_ count: Int) throws -> [UInt8] {
    guard count >= 0, data.endIndex - offset >= count else { throw ByteReaderError.endOfData }
    let start = offset
    offset = data.index(start, offsetBy: count)
    return Array(data[start..<offset])
  }

  mutating func skip(_ count: Int) throws {
    guard count >= 0, data.endIndex - offset >= count else { throw ByteReaderError.endOfData }
    offset = data.index(offset, offsetBy: count)
  }

  mutating func readUInt32() throws -> UInt32 {
    let b = try read(4)
    return UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
  }

  mutating func readFourCC() throws -> String {
    let b = try read(4)
    guard let s = String(bytes: b, encoding: .ascii) else { throw ByteReaderError.invalidString }
    return s
  }
}

struct RIFFHeader {
  let signature: String
  let fileSizeLE: UInt32
  let formType: String
}

struct RIFFChunk {
  let fourCC: String
  let sizeLE: UInt32
  let dataStartOffset: Int
}

enum WebPListError: Error {
  case invalidSignature(String)
  case notWEBP(String)
  case truncatedRIFF
  case chunkOutOfRange(fourCC: String)
}
