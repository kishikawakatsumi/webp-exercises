// reverseBits reverses the bits in a byte.
let reverseBits: [UInt8] = [
  0x00, 0x80, 0x40, 0xc0, 0x20, 0xa0, 0x60, 0xe0, 0x10, 0x90, 0x50, 0xd0, 0x30, 0xb0, 0x70, 0xf0,
  0x08, 0x88, 0x48, 0xc8, 0x28, 0xa8, 0x68, 0xe8, 0x18, 0x98, 0x58, 0xd8, 0x38, 0xb8, 0x78, 0xf8,
  0x04, 0x84, 0x44, 0xc4, 0x24, 0xa4, 0x64, 0xe4, 0x14, 0x94, 0x54, 0xd4, 0x34, 0xb4, 0x74, 0xf4,
  0x0c, 0x8c, 0x4c, 0xcc, 0x2c, 0xac, 0x6c, 0xec, 0x1c, 0x9c, 0x5c, 0xdc, 0x3c, 0xbc, 0x7c, 0xfc,
  0x02, 0x82, 0x42, 0xc2, 0x22, 0xa2, 0x62, 0xe2, 0x12, 0x92, 0x52, 0xd2, 0x32, 0xb2, 0x72, 0xf2,
  0x0a, 0x8a, 0x4a, 0xca, 0x2a, 0xaa, 0x6a, 0xea, 0x1a, 0x9a, 0x5a, 0xda, 0x3a, 0xba, 0x7a, 0xfa,
  0x06, 0x86, 0x46, 0xc6, 0x26, 0xa6, 0x66, 0xe6, 0x16, 0x96, 0x56, 0xd6, 0x36, 0xb6, 0x76, 0xf6,
  0x0e, 0x8e, 0x4e, 0xce, 0x2e, 0xae, 0x6e, 0xee, 0x1e, 0x9e, 0x5e, 0xde, 0x3e, 0xbe, 0x7e, 0xfe,
  0x01, 0x81, 0x41, 0xc1, 0x21, 0xa1, 0x61, 0xe1, 0x11, 0x91, 0x51, 0xd1, 0x31, 0xb1, 0x71, 0xf1,
  0x09, 0x89, 0x49, 0xc9, 0x29, 0xa9, 0x69, 0xe9, 0x19, 0x99, 0x59, 0xd9, 0x39, 0xb9, 0x79, 0xf9,
  0x05, 0x85, 0x45, 0xc5, 0x25, 0xa5, 0x65, 0xe5, 0x15, 0x95, 0x55, 0xd5, 0x35, 0xb5, 0x75, 0xf5,
  0x0d, 0x8d, 0x4d, 0xcd, 0x2d, 0xad, 0x6d, 0xed, 0x1d, 0x9d, 0x5d, 0xdd, 0x3d, 0xbd, 0x7d, 0xfd,
  0x03, 0x83, 0x43, 0xc3, 0x23, 0xa3, 0x63, 0xe3, 0x13, 0x93, 0x53, 0xd3, 0x33, 0xb3, 0x73, 0xf3,
  0x0b, 0x8b, 0x4b, 0xcb, 0x2b, 0xab, 0x6b, 0xeb, 0x1b, 0x9b, 0x5b, 0xdb, 0x3b, 0xbb, 0x7b, 0xfb,
  0x07, 0x87, 0x47, 0xc7, 0x27, 0xa7, 0x67, 0xe7, 0x17, 0x97, 0x57, 0xd7, 0x37, 0xb7, 0x77, 0xf7,
  0x0f, 0x8f, 0x4f, 0xcf, 0x2f, 0xaf, 0x6f, 0xef, 0x1f, 0x9f, 0x5f, 0xdf, 0x3f, 0xbf, 0x7f, 0xff,
]

struct HNode {
  var symbol: UInt32 = 0
  var children: Int32 = 0
}

let leafNode: Int32 = -1

let lutSize = 7
let lutMask = (1 << lutSize) - 1

struct HTree {
  var nodes: [HNode] = []
  var lut: [UInt32] = Array(repeating: 0, count: 1 << lutSize)

  mutating func insert(symbol: UInt32, code: UInt32, codeLength: UInt32) throws {
    guard symbol <= 0xffff, codeLength <= 0xfe else {
      throw VP8LError.invalidHuffmanTree
    }

   var baseCode: UInt32 = 0

    if codeLength > UInt32(lutSize) {
      let idx = Int((code >> (codeLength - UInt32(lutSize))) & 0xff)
      baseCode = UInt32(reverseBits[idx]) >> (8 - lutSize)
    } else {
      let idx = Int(code & 0xff)
      baseCode = UInt32(reverseBits[idx]) >> (8 - codeLength)

      let span = 1 << (lutSize - Int(codeLength))
      for i in 0..<span {
        let lutIdx = Int(baseCode | (UInt32(i) << codeLength))
        lut[lutIdx] = (symbol << 8) | (codeLength + 1)
      }
    }

    var n: UInt32 = 0
    var remBits = codeLength
    var jump = lutSize

    while remBits > 0 {
      remBits -= 1

      guard n < UInt32(nodes.count) else {
        throw VP8LError.invalidHuffmanTree
      }

      switch nodes[Int(n)].children {
      case leafNode:
        throw VP8LError.invalidHuffmanTree
      case 0:
        nodes[Int(n)].children = Int32(nodes.count)
        nodes.append(HNode())
        nodes.append(HNode())
      default:
        break
      }

      let bit = (code >> remBits) & 1
      n = UInt32(nodes[Int(n)].children) + bit

      jump -= 1
      if jump == 0 && lut[Int(baseCode)] == 0 {
        lut[Int(baseCode)] = n << 8
      }
    }

    switch nodes[Int(n)].children {
    case leafNode:
      break
    case 0:
      nodes[Int(n)].children = leafNode
    default:
      throw VP8LError.invalidHuffmanTree
    }

    nodes[Int(n)].symbol = symbol
  }

  func codeLengthsToCodes(_ codeLengths: [UInt32]) throws -> [UInt32] {
    let maxAllowedCodeLength = 15
    guard let maxCodeLength = codeLengths.max() else {
      throw VP8LError.invalidHuffmanTree
    }
    guard !codeLengths.isEmpty, maxCodeLength <= maxAllowedCodeLength else {
      throw VP8LError.invalidHuffmanTree
    }

    var histogram = [UInt32](repeating: 0, count: maxAllowedCodeLength + 1)
    for cl in codeLengths {
      histogram[Int(cl)] &+= 1
    }

   var nextCodes = [UInt32](repeating: 0, count: maxAllowedCodeLength + 1)
    var currCode: UInt32 = 0
    for cl in 1...maxAllowedCodeLength {
      currCode = (currCode &+ histogram[cl - 1]) << 1
      nextCodes[cl] = currCode
    }

    var codes = [UInt32](repeating: 0, count: codeLengths.count)
    for (symbol, cl) in codeLengths.enumerated() where cl > 0 {
      let len = Int(cl)
      codes[symbol] = nextCodes[len]
      nextCodes[len] &+= 1
    }

    return codes
  }

  mutating func build(_ codeLengths: [UInt32]) throws {
    // Calculate the number of symbols.
    var nSymbols: UInt32   = 0
    var lastSymbol: UInt32 = 0

    for (sym, cl) in codeLengths.enumerated() where cl != 0 {
      nSymbols   &+= 1
      lastSymbol  = UInt32(sym)
    }

    guard nSymbols > 0 else {
      throw VP8LError.invalidHuffmanTree
    }

    nodes = [HNode()]
    nodes.reserveCapacity(Int(2 * nSymbols - 1))
    lut = Array(repeating: 0, count: 1 << lutSize)

    if nSymbols == 1 {
      guard lastSymbol < UInt32(codeLengths.count) else {
        throw VP8LError.invalidHuffmanTree
      }
      try self.insert(symbol: lastSymbol, code: 0, codeLength: 0)
      return
    }

    let codes = try codeLengthsToCodes(codeLengths)

    for (symbol, cl) in codeLengths.enumerated() where cl > 0 {
      try self.insert(
        symbol: UInt32(symbol),
        code: codes[symbol],
        codeLength: cl
      )
    }
  }

  mutating func buildSimple(
    nSymbols: UInt32,
    symbols:  [UInt32],
    alphabetSize: UInt32
  ) throws {
    nodes = [HNode()]
    nodes.reserveCapacity(Int(2 * nSymbols - 1))
    lut = Array(repeating: 0, count: 1 << lutSize)

    for i in 0..<nSymbols {
      let sym = symbols[Int(i)]
      guard sym < alphabetSize else {
        throw VP8LError.invalidHuffmanTree
      }

      try self.insert(
        symbol: sym,
        code: i,
        codeLength: nSymbols - 1
      )
    }
  }

  mutating func next(decoder d: inout VP8LDecoder) throws -> UInt32 {
    if d.nBits < UInt32(lutSize) {
      if let byte = try d.reader.read() {
        d.bits |= UInt32(byte) << d.nBits
        d.nBits &+= 8
      }
    }

    var n = lut[Int(d.bits) & lutMask]

    if n & 0xFF != 0 {
      let b = (n & 0xFF) - 1
      d.bits >>= b
      d.nBits &-= b
      return n >> 8
    }

    n >>= 8
    d.bits >>= lutSize
    d.nBits &-= UInt32(lutSize)

    while nodes[Int(n)].children != leafNode {
      if d.nBits == 0 {
        guard let byte = try d.reader.read() else {
          throw BitStreamError.unexpectedEOF
        }
        d.bits  = UInt32(byte)
        d.nBits = 8
      }

      let bit = d.bits & 1
      n = UInt32(nodes[Int(n)].children) &+ bit
      d.bits >>= 1
      d.nBits &-= 1
    }

    return nodes[Int(n)].symbol
  }
}
