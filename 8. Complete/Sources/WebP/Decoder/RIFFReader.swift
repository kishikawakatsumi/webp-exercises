import Foundation

private let chunkHeaderSize = 8

final class RIFFReader {
  fileprivate var byteReader: ByteReader

  fileprivate var error: Error? = nil
  fileprivate var totalLen: UInt32
  fileprivate var chunkLen: UInt32 = 0
  private var padded = false

  private var buf = [UInt8](repeating: 0, count: chunkHeaderSize)

  init(data: Data, totalLen: UInt32) {
    self.byteReader = ByteReader(data)
    self.totalLen = totalLen
  }

  static func makeReader(from data: Data) throws -> (formType: FourCC, reader: RIFFReader) {
    guard data.count >= chunkHeaderSize else {
      throw WebPError.missingRIFFChunkHeader
    }

    guard FourCC(data[0], data[1], data[2], data[3]) == .riff else {
      throw WebPError.missingRIFFChunkHeader
    }

    let size = u32(data[4..<8])
    guard size >= 4, data.count >= 8 + 4 else {
      throw WebPError.shortChunkData
    }

    let form = FourCC(data[8], data[9], data[10], data[11])
    let payloadStart = 12
    let payloadLen = Int(size) - 4

    guard payloadStart + payloadLen <= data.count else {
      throw WebPError.shortChunkData
    }

    let subData = data.subdata(in: payloadStart ..< payloadStart + payloadLen)
    return (form, RIFFReader(data: subData, totalLen: UInt32(payloadLen)))
  }

  func next() throws -> (FourCC, UInt32) {
    if let e = error {
      throw e
    }

    if chunkLen != 0 {
      try byteReader.skip(Int(chunkLen))
      chunkLen = 0
    }

    if padded {
      guard totalLen > 0 else {
        throw WebPError.listSubchunkTooLong
      }
      totalLen -= 1
      _ = try byteReader.read(1) // ignore
      padded = false
    }

    guard totalLen > 0 else {
      throw EOFError()
    }

    guard totalLen >= chunkHeaderSize else {
      throw WebPError.shortChunkHeader
    }
    totalLen -= UInt32(chunkHeaderSize)

    buf = try byteReader.read(chunkHeaderSize)
    let id = FourCC(buf[0], buf[1], buf[2], buf[3])
    chunkLen = u32(Data(buf[4...]))

    guard chunkLen <= totalLen else {
      throw WebPError.listSubchunkTooLong
    }

    padded = (chunkLen & 1) == 1

    return (id, chunkLen)
  }

  func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
    if let e = error {
      if e is EOFError {
        error = WebPError.staleReader
      }
      return -1
    }

    var n = Int(chunkLen)
    if n == 0 {
      return 0
    }

    if n < 0 {
      n = Int(Int32.max)
    }

    let want = min(n, len)
    do {
      let bytes = try byteReader.read(want)
      buffer.update(from: bytes, count: want)

      totalLen &-= UInt32(want)
      chunkLen &-= UInt32(want)

      return want
    } catch let e {
      error = e
      return -1
    }
  }

  func readByte() -> UInt8? {
    var byte: UInt8 = 0
    let n = read(&byte, maxLength: 1)
    return n == 1 ? byte : nil
  }
}

@inline(__always)
private func u32(_ data: Data) -> UInt32 {
  return UInt32(data[data.startIndex + 0])
  | UInt32(data[data.startIndex + 1]) << 8
  | UInt32(data[data.startIndex + 2]) << 16
  | UInt32(data[data.startIndex + 3]) << 24
}
