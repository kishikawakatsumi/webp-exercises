public struct BitWriter {
  public var buffer = [UInt8]()
  var bitBuffer: UInt64 = 0
  var bitBufferSize = 0

  public mutating func writeBits(_ value: UInt64, _ n: Int) {
    precondition(n >= 0 && n <= 64, "Invalid bit count: must be between 0 and 64")
    precondition(value < 1 &<< UInt64(n), "too many bits for the given value")

    bitBuffer |= (value &<< UInt64(bitBufferSize))
    bitBufferSize += n
    writeThrough()
  }

  public mutating func writeBytes(_ values: [UInt8]) {
    for value in values {
      writeBits(UInt64(value), 8)
    }
  }

  public mutating func writeCode(_ code: HuffmanCode) {
    if code.depth <= 0 { return }
    var v = code.bits
    var rev: UInt64 = 0
    for _ in 0..<code.depth {
      rev = (rev &<< 1) | (v & 1)
      v &>>= 1
    }
    writeBits(rev, code.depth)
  }

  public mutating func alignByte() {
    bitBufferSize = (bitBufferSize + 7) & ~7
    writeThrough()
  }

  mutating func writeThrough() {
    while bitBufferSize >= 8 {
      buffer.append(UInt8(truncatingIfNeeded: bitBuffer & 0xFF))
      bitBuffer &>>= 8
      bitBufferSize -= 8
    }
  }
}
