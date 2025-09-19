import Foundation

enum VP8LHeaderError: Error {
  case invalidHeader
  case invalidVersion
}

enum VP8LError: Error {
  case invalidCodeLengths
  case invalidHuffmanTree
  case invalidColorCacheParameters
  case invalidLZ77Parameters
  case invalidColorCacheIndex
}

private let colorCacheMultiplier: UInt32 = 0x1e35a7bd

private let distanceMapTable: [UInt8] = [
  0x18, 0x07, 0x17, 0x19, 0x28, 0x06, 0x27, 0x29, 0x16, 0x1a,
  0x26, 0x2a, 0x38, 0x05, 0x37, 0x39, 0x15, 0x1b, 0x36, 0x3a,
  0x25, 0x2b, 0x48, 0x04, 0x47, 0x49, 0x14, 0x1c, 0x35, 0x3b,
  0x46, 0x4a, 0x24, 0x2c, 0x58, 0x45, 0x4b, 0x34, 0x3c, 0x03,
  0x57, 0x59, 0x13, 0x1d, 0x56, 0x5a, 0x23, 0x2d, 0x44, 0x4c,
  0x55, 0x5b, 0x33, 0x3d, 0x68, 0x02, 0x67, 0x69, 0x12, 0x1e,
  0x66, 0x6a, 0x22, 0x2e, 0x54, 0x5c, 0x43, 0x4d, 0x65, 0x6b,
  0x32, 0x3e, 0x78, 0x01, 0x77, 0x79, 0x53, 0x5d, 0x11, 0x1f,
  0x64, 0x6c, 0x42, 0x4e, 0x76, 0x7a, 0x21, 0x2f, 0x75, 0x7b,
  0x31, 0x3f, 0x63, 0x6d, 0x52, 0x5e, 0x00, 0x74, 0x7c, 0x41,
  0x4f, 0x10, 0x20, 0x62, 0x6e, 0x30, 0x73, 0x7d, 0x51, 0x5f,
  0x40, 0x72, 0x7e, 0x61, 0x6f, 0x50, 0x71, 0x7f, 0x60, 0x70,
]

@inline(__always)
private func distanceMap(width w: Int32, code: UInt32) -> Int32 {
  if Int32(code) > Int32(distanceMapTable.count) {
    return Int32(code) - Int32(distanceMapTable.count)
  }
  let distCode = Int32(distanceMapTable[Int(code - 1)])
  let yOffset = distCode >> 4
  let xOffset = 8 - (distCode & 0xF)

  let d = yOffset &* w &+ xOffset
  if d >= 1 {
    return d
  }
  return 1
}

private let repeatsCodeLength: UInt32 = 16

private let codeLengthCodeOrder: [UInt8] = [
  17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
]
private let repeatBits:  [UInt8] = [2, 3, 7]
private let repeatOffsets: [UInt8] = [3, 3, 11]

struct VP8LDecoder {
  var bits: UInt32 = 0
  var nBits: UInt32 = 0

  var reader: ByteReader

  init(data: Data) {
    self.reader = ByteReader(data)
  }

  mutating func decode() throws -> NRGBAImage {
    var (width, height) = try decodeHeader()
    let originalWidth = width

    var transforms: [Transform] = []
    var seenTransform = Set<TransformType>()

    while true {
      let more = try read(1)
      if more == 0 { break }

      let (t, newW) = try decodeTransform(width: width, height: height)
      guard seenTransform.insert(t.type).inserted else {
        throw VP8LDecodingError.repeatedTransform
      }

      transforms.append(t)
      width = newW
    }

    var pixels = try decodePixels(
      width: width,
      height: height,
      minCapacity: 0,
      isTopLevel: true
    )

    for t in transforms.reversed() {
      pixels = inverseTransforms[Int(t.type.rawValue)](t, pixels, height)
    }

    return NRGBAImage(
      pixels: pixels,
      stride: Int(originalWidth) * 4,
      width: Int(originalWidth),
      height: Int(height)
    )
  }

  mutating func decodeHeader() throws -> (width: Int32, height: Int32) {
    let magic = try read(8)
    guard magic == 0x2f else {
      throw VP8LHeaderError.invalidHeader
    }

    let width = Int32(try read(14) + 1)
    let height = Int32(try read(14) + 1)

    _ = try read(1) // Read and ignore the hasAlpha hint.

    let version = try read(3)
    guard version == 0 else {
      throw VP8LHeaderError.invalidVersion
    }

    return (width, height)
  }

  mutating func decodeTransform(width w: Int32, height h: Int32) throws -> (Transform, Int32) {
    var t = Transform()
    t.oldWidth = w

    let rawTransformType = try read(2)
    guard let transformType = TransformType(rawValue: rawTransformType) else {
      throw VP8LError.invalidHuffmanTree
    }
    t.type = transformType

    var newWidth = w

    switch transformType {
    case .predictor, .crossColor:
      t.bits = try read(3)
      t.bits &+= 2
      let tileW = numberOfTiles(w, bits: t.bits)
      let tileH = numberOfTiles(h, bits: t.bits)
      t.pix = try decodePixels(
        width: tileW,
        height: tileH,
        minCapacity: 0,
        isTopLevel: false
      )
    case .subtractGreen:
      break
    case .colorIndexing:
      var nColors = try read(8)
      nColors &+= 1

      switch nColors {
      case 0...2:
        t.bits = 3
      case 3...4:
        t.bits = 2
      case 5...16:
        t.bits = 1
      default:
        t.bits = 0
      }

      newWidth = numberOfTiles(w, bits: t.bits)
      var palette = try decodePixels(
        width: Int32(nColors),
        height: 1,
        minCapacity: 4 * 256,
        isTopLevel: false
      )

      for i in stride(from: 4, to: palette.count, by: 4) {
        palette[i + 0] = palette[i + 0] &+ palette[i - 4]
        palette[i + 1] = palette[i + 1] &+ palette[i - 3]
        palette[i + 2] = palette[i + 2] &+ palette[i - 2]
        palette[i + 3] = palette[i + 3] &+ palette[i - 1]
      }

      var fullPalette = [UInt8](repeating: 0, count: 4 * 256)
      fullPalette.replaceSubrange(0..<palette.count, with: palette)
      t.pix = fullPalette
    }

    return (t, newWidth)
  }

  mutating func decodeCodeLengths(into dst: inout [UInt32], codeLengthCodeLengths: [UInt32]) throws {
    var h = HTree()
    try h.build(codeLengthCodeLengths)

    var maxSymbol = dst.count
    let useLength = try self.read(1)
    if useLength != 0 {
      var n = try self.read(3)
      n = 2 &+ 2 &* n
      let ms = try self.read(n)
      maxSymbol = Int(ms) + 2
      guard maxSymbol <= dst.count else {
        throw VP8LError.invalidCodeLengths
      }
    }

    var prevCodeLength: UInt32 = 8
    var symbol = 0

    while symbol < dst.count {
      if maxSymbol == 0 {
        break
      }
      maxSymbol -= 1

      let codeLength = try h.next(decoder: &self)

      if codeLength < repeatsCodeLength {
        dst[symbol] = codeLength
        symbol += 1
        if codeLength != 0 {
          prevCodeLength = codeLength
        }
        continue
      }

      let idx = Int(codeLength) - Int(repeatsCodeLength)
      let bitsToRead = UInt32(repeatBits[idx])
      var repeatCount = try self.read(bitsToRead)
      repeatCount += UInt32(repeatOffsets[idx])

      guard symbol + Int(repeatCount) <= dst.count else {
        throw VP8LError.invalidCodeLengths
      }

      let cl: UInt32 = (codeLength == 16) ? prevCodeLength : 0
      for _ in 0..<repeatCount {
        dst[symbol] = cl
        symbol += 1
      }
    }
  }

  mutating func decodeHuffmanTree(_ tree: inout HTree, alphabetSize: UInt32) throws {
    let useSimple = try read(1)
    if useSimple != 0 {
      var nSymbols = try read(1)
      nSymbols += 1

      var firstSymbolLengthCode = try read(1)
      firstSymbolLengthCode = 7 &* firstSymbolLengthCode &+ 1

      var symbols = [UInt32](repeating: 0, count: 2)
      symbols[0] = try read(firstSymbolLengthCode)

      if nSymbols == 2 {
        symbols[1] = try read(8)
      }

      try tree.buildSimple(
        nSymbols: nSymbols,
        symbols: symbols,
        alphabetSize: alphabetSize
      )
      return
    }

    var nCodes = try read(4)
    nCodes += 4
    guard Int(nCodes) <= codeLengthCodeOrder.count else {
      throw VP8LError.invalidHuffmanTree
    }

    var codeLengthCodeLengths = [UInt32](repeating: 0, count: codeLengthCodeOrder.count)
    for i in 0..<nCodes {
      let idx = Int(codeLengthCodeOrder[Int(i)])
      codeLengthCodeLengths[idx] = try read(3)
    }

    var codeLengths = [UInt32](repeating: 0, count: Int(alphabetSize))
    try self.decodeCodeLengths(
      into: &codeLengths,
      codeLengthCodeLengths: codeLengthCodeLengths
    )

    try tree.build(codeLengths)
  }

  mutating func decodeHuffmanGroups(
    width: Int32,
    height: Int32,
    isTopLevel: Bool,
    colorCacheBits ccBits: UInt32
  ) throws -> (
    groups: [HuffmanGroup],
    entropyImageBytes: [UInt8],
    tileBits: UInt32
  ) {
    var maxHuffmanGroupIndex = 0
    var entropyImageBytes: [UInt8] = []
    var tileBits: UInt32  = 0

    if isTopLevel {
      let hasEntropyImage = try read(1)
      if hasEntropyImage != 0 {
        tileBits = try read(3)
        tileBits &+= 2

        entropyImageBytes = try decodePixels(
          width: numberOfTiles(width, bits: tileBits),
          height: numberOfTiles(height, bits: tileBits),
          minCapacity: 0,
          isTopLevel: false
        )

        for p in stride(from: 0, to: entropyImageBytes.count, by: 4) {
          let i = Int(entropyImageBytes[p]) << 8 | Int(entropyImageBytes[p + 1])
          if i > maxHuffmanGroupIndex {
            maxHuffmanGroupIndex = i
          }
        }
      }
    }

    var groups = [HuffmanGroup](
      repeating: [HTree](repeating: HTree(), count: nHuff),
      count: maxHuffmanGroupIndex + 1
    )

    for i in 0 ..< groups.count {
      for (j, baseAlphabet) in alphabetSizes.enumerated() {
        var alphabet = baseAlphabet
        if j == 0 && ccBits > 0 {
          alphabet += 1 << ccBits
        }
        try decodeHuffmanTree(
          &groups[i][j],
          alphabetSize: alphabet
        )
      }
    }

    return (groups, entropyImageBytes, tileBits)
  }

  mutating func decodePixels(
    width: Int32,
    height: Int32,
    minCapacity minCap: Int32 = 0,
    isTopLevel: Bool
  ) throws -> [UInt8] {
    // Decode the color cache parameters.
    var colorCacheBits: UInt32 = 0
    var colorCacheShift: UInt32 = 0
    var colorCacheEntries: [UInt32] = []

    let useColorCache = try read(1)
    if useColorCache != 0 {
      colorCacheBits = try read(4)
      guard (1...11).contains(colorCacheBits) else {
        throw VP8LError.invalidColorCacheParameters
      }

      colorCacheShift = 32 &- colorCacheBits
      colorCacheEntries = [UInt32](repeating: 0, count: 1 << colorCacheBits)
    }

    let (huffmanGroups, entropyImageBytes, tileBits) = try decodeHuffmanGroups(
      width: width,
      height: height,
      isTopLevel: isTopLevel,
      colorCacheBits: colorCacheBits
    )

    let tileMask: Int32
    let tilesPerRow: Int32
    if tileBits == 0 {
      tileMask = 0
      tilesPerRow = 0
    } else {
      tileMask = (1 << tileBits) &- 1
      tilesPerRow = numberOfTiles(width, bits: tileBits)
    }

    let pixelCount = Int(width * height)
    var pix = [UInt8](repeating: 0, count: pixelCount * 4)
    if minCap > 0 {
      pix.reserveCapacity(Int(minCap))
    }

    var p = 0
    var cachedP = 0
    var x: Int32 = 0
    var y: Int32 = 0
    var hgIndex = 0 // current Huffman-group index
    var lookupHG = (tileBits != 0)

    while p < pix.count {
      if lookupHG {
        let tileX = x >> tileBits
        let tileY = y >> tileBits
        let i = Int(4 * (tilesPerRow * tileY + tileX))
        hgIndex = Int(entropyImageBytes[i]) << 8 | Int(entropyImageBytes[i + 1])
      }
      var hg = huffmanGroups[hgIndex]

      let green = try hg[huffGreen].next(decoder: &self)

      switch green {
      case 0 ..< UInt32(nLiteralCodes):
        let red = try hg[huffRed].next(decoder: &self)
        let blue = try hg[huffBlue].next(decoder: &self)
        let alpha = try hg[huffAlpha].next(decoder: &self)

        pix[p + 0] = UInt8(red)
        pix[p + 1] = UInt8(green)
        pix[p + 2] = UInt8(blue)
        pix[p + 3] = UInt8(alpha)
        p += 4

        x &+= 1
        if x == width {
          x = 0
          y &+= 1
        }

        lookupHG = (tileBits != 0) && (x & tileMask == 0)
      case UInt32(nLiteralCodes) ..< UInt32(nLiteralCodes + nLengthCodes):
        // We have a LZ77 backwards reference.
        let length = try self.lz77Param(green - UInt32(nLiteralCodes))
        let distSym = try hg[huffDistance].next(decoder: &self)
        let distCod = try self.lz77Param(distSym)
        let dist = distanceMap(width: width, code: distCod)

        let bytes = Int(length) * 4
        let pEnd = p + bytes
        let qStart = p - Int(dist) * 4
        let qEnd = qStart + bytes

        guard p >= 0, pEnd <= pix.count, qStart >= 0, qEnd <= pix.count else {
          throw VP8LError.invalidLZ77Parameters
        }

        for i in 0..<bytes { pix[p + i] = pix[qStart + i] }
        p = pEnd

        x &+= Int32(length)
        while x >= width { x &-= width; y &+= 1 }

        lookupHG = (tileBits != 0)
      default:
        while cachedP < p {
          let argb = UInt32(pix[cachedP + 0]) << 16 |
          UInt32(pix[cachedP + 1]) <<  8 |
          UInt32(pix[cachedP + 2]) <<  0 |
          UInt32(pix[cachedP + 3]) << 24
          let idx  = Int((argb &* colorCacheMultiplier) >> colorCacheShift)
          colorCacheEntries[idx] = argb
          cachedP += 4
        }

        let cacheIdx = green - UInt32(nLiteralCodes + nLengthCodes)
        guard cacheIdx < colorCacheEntries.count else {
          throw VP8LError.invalidColorCacheIndex
        }
        let argb = colorCacheEntries[Int(cacheIdx)]

        pix[p + 0] = UInt8(argb >> 16 & 0xFF)
        pix[p + 1] = UInt8(argb >>  8 & 0xFF)
        pix[p + 2] = UInt8(argb >>  0 & 0xFF)
        pix[p + 3] = UInt8(argb >> 24 & 0xFF)
        p += 4

        x &+= 1
        if x == width { x = 0; y &+= 1 }
        lookupHG = (tileBits != 0) && (x & tileMask == 0)
      }
    }

    return pix
  }

  mutating func lz77Param(_ symbol: UInt32) throws -> UInt32 {
    if symbol < 4 {
      return symbol &+ 1
    }

    let extraBits = (symbol &- 2) >> 1
    let offset = (2 &+ (symbol & 1)) << extraBits

    let n = try self.read(extraBits)

    return offset &+ n &+ 1
  }

  mutating func read(_ n: UInt32) throws -> UInt32 {
    precondition((1...32).contains(n), "n must be in 1…32")

    while nBits < n {
      guard let byte = try reader.read() else {
        throw BitStreamError.unexpectedEOF
      }
      bits |= UInt32(byte) << nBits
      nBits += 8
    }

    let result = bits & ((1 << n) &- 1)

    bits >>= n
    nBits -= n

    return result
  }
}

private let huffGreen = 0
private let huffRed = 1
private let huffBlue = 2
private let huffAlpha = 3
private let huffDistance = 4
private let nHuff = 5

typealias HuffmanGroup = [HTree]

private let nLiteralCodes = 256
private let nLengthCodes = 24
private let nDistanceCodes = 40

private let alphabetSizes: [UInt32] = [
  UInt32(nLiteralCodes + nLengthCodes),
  UInt32(nLiteralCodes),
  UInt32(nLiteralCodes),
  UInt32(nLiteralCodes),
  UInt32(nDistanceCodes),
]

public struct NRGBAImage {
  public var pixels: [UInt8]
  public var stride: Int
  public var width: Int
  public var height: Int
}

enum VP8LDecodingError: Error {
  case repeatedTransform
}

enum BitStreamError: Error {
  case unexpectedEOF
}
