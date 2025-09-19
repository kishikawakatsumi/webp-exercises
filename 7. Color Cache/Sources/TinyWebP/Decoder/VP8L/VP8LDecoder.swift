import Foundation

// 0..18 の CLアルファベット（0..15=長さ値, 16/17/18=RLE）
private let CL_ALPHABET_SIZE = 19
private let REPEAT_16: UInt32 = 16  // 直前の非0長を 3..6 回
private let REPEAT_17: UInt32 = 17  // 0 を 3..10 回
private let REPEAT_18: UInt32 = 18  // 0 を 11..138 回

// 16/17/18 の extra ビット数と base 値
private let RLE_EXTRA_BITS: [Int] = [2, 3, 7]   // for 16,17,18
private let RLE_BASE: [Int] = [3, 3, 11]  // for 16,17,18

private let TREE_G    = 0  // G / 長さ / ColorCache
private let TREE_R    = 1
private let TREE_B    = 2
private let TREE_A    = 3
private let TREE_DIST = 4

private let N_LITERAL_CODES = 256
private let N_LENGTH_CODES  = 24

typealias HuffmanGroup = [[DecNode]]

struct VP8LDecoder {
  var bits: UInt32 = 0
  var nBits: UInt32 = 0

  var reader: ByteReader

  init(data: Data) {
    self.reader = ByteReader(data)
  }

  mutating func decode() throws -> NRGBAImage {
    let (width, height) = try decodeHeader()

    while true {
      let more = try read(1)
      if more == 0 {
        break
      }

      // No transforms are supported yet.
    }

    let pix = try decodePixelBuffer(
      width: width,
      height: height,
      reserveCapacity: 0,
      isTopLevel: true
    )

    return NRGBAImage(
      pixels: pix,
      stride: Int(width) * 4,
      width: Int(width),
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

  mutating func decodePixelBuffer(
    width w: Int32,
    height h: Int32,
    reserveCapacity: Int32 = 0,
    isTopLevel: Bool
  ) throws -> [UInt8] {

    let useColorCache = try read(1) != 0
    if useColorCache {
      throw VP8LError.notImplemented
    }

    let groups = try decodeHuffmanGroups(
      width: Int(w), height: Int(h), isTopLevel: isTopLevel
    )
    // 可読版では単一グループのみ（HTree image 未実装）
    precondition(groups.count == 1, "entropy image / multiple groups is not implemented")
    let trees = groups[0]  // [G, R, B, A, Dist]

    // ---- 2) 出力バッファを用意 ----
    let pixelCount = Int(w * h)
    var rgba = [UInt8](repeating: 0, count: pixelCount * 4)
    if reserveCapacity > 0 {
      rgba.reserveCapacity(Int(reserveCapacity))
    }

    // ---- 3) 走査して 1 画素ずつ復号（LZ77 なし→常にリテラルの想定）----
    var x: Int32 = 0
    var y: Int32 = 0
    var p = 0  // rgba の書き込み位置

    while p < rgba.count {
      // Gツリーから最初の記号（v0）を取得
      let gTok = try readToken(with: trees[TREE_G])

      switch gTok {
      case 0 ..< N_LITERAL_CODES:
        // --- リテラル画素（G= gTok、続けて R/B/A を読む）---
        let rTok = try readToken(with: trees[TREE_R])
        let bTok = try readToken(with: trees[TREE_B])
        let aTok = try readToken(with: trees[TREE_A])

        rgba[p + 0] = UInt8(rTok)
        rgba[p + 1] = UInt8(gTok)
        rgba[p + 2] = UInt8(bTok)
        rgba[p + 3] = UInt8(aTok)
        p += 4

        x &+= 1
        if x == w {
          x = 0
          y &+= 1
        }

      case N_LITERAL_CODES..<(N_LITERAL_CODES + N_LENGTH_CODES):
        throw VP8LError.notImplemented
      default:
        throw VP8LError.invalidBitstream
      }
    }

    return rgba
  }

  mutating func decodeHuffmanGroups(
    width: Int,
    height: Int,
    isTopLevel: Bool
  ) throws -> [HuffmanGroup] {
    let groupCount = 1

    if isTopLevel {
      let hasEntropyImage = try read(1) != 0
      if hasEntropyImage {
        throw VP8LError.notImplemented
      }
    }

    var groups: [HuffmanGroup] = []
    groups.reserveCapacity(groupCount)

    for _ in 0..<groupCount {
      var trees: [[DecNode]] = []
      trees.reserveCapacity(alphabetSizes.count)

      for alphaSize in alphabetSizes {
        let tree = try decodePrefixCode(alphabetSize: Int(alphaSize))
        trees.append(tree)
      }
      groups.append(trees)
    }

    return groups
  }

  mutating func decodePrefixCode(alphabetSize: Int) throws -> [DecNode] {
    let isSimple = try read(1) != 0
    if isSimple {
      let nSymbols = Int(try read(1)) + 1

      let firstLen = (try read(1) != 0) ? 8 : 1
      let s0 = Int(try read(UInt32(firstLen)))
      var nodes = [DecNode()]
      if nSymbols == 1 {
        nodes[0].sym = s0
        return nodes
      } else {
        let s1 = Int(try read(8))

        nodes.append(DecNode(sym: s0))
        nodes.append(DecNode(sym: s1))

        nodes[0].left  = 1
        nodes[0].right = 2

        return nodes
      }
    }

    let nCodes = Int(try read(4)) + 4
    precondition(nCodes <= lengthCodeOrder.count)

    var clCodeLengths = [UInt8](repeating: 0, count: lengthCodeOrder.count)
    for i in 0..<nCodes {
      clCodeLengths[lengthCodeOrder[i]] = UInt8(try read(3))  // 0..7
    }

    let clTree = try buildDecodingTree(from: clCodeLengths, maxLen: 7)

    var L = [UInt8](repeating: 0, count: alphabetSize)

    var remaining = alphabetSize
    let useMax = try read(1) != 0
    if useMax {
      let k = Int(try read(3))
      let n = 2 + 2*k
      let ms = Int(try read(UInt32(n))) + 2
      precondition(ms <= alphabetSize)
      remaining = ms
    }

    var i = 0
    var prevLen: UInt8 = 8

    while i < alphabetSize {
      if remaining == 0 { break }
      remaining -= 1

      let tok = try readToken(with: clTree)
      if tok < 16 {
        L[i] = UInt8(tok)
        if tok != 0 {
          prevLen = UInt8(tok)
        }
        i += 1
        continue
      }

      let idx = tok - 16
      let extraBits = RLE_EXTRA_BITS[idx]
      let base = RLE_BASE[idx]
      let run = base + Int(try read(UInt32(extraBits)))
      let fill: UInt8 = (tok == REPEAT_16) ? prevLen : 0
      precondition(i + run <= alphabetSize)
      for _ in 0..<run {
        L[i] = fill
        i += 1
      }
    }
    while i < alphabetSize {
      L[i] = 0
      i += 1
    }

    let tree = try buildDecodingTree(from: L, maxLen: 15)
    return tree
  }

  private func buildDecodingTree(from codeLengths: [UInt8], maxLen: Int) throws -> [DecNode] {
    let used = codeLengths
      .enumerated()
      .filter { $0.element > 0 }
      .map { $0.offset }

    guard !used.isEmpty else {
      throw HuffBuildError.invalidTree
    }

    if used.count == 1 {
      var nodes = [DecNode()]
      nodes[0].sym = used[0]
      return nodes
    }

    var bl = [Int](repeating: 0, count: maxLen + 1)
    for L in codeLengths where L > 0 { bl[Int(L)] += 1 }

    var first = [UInt32](repeating: 0, count: maxLen + 1)
    var running: UInt32 = 0
    for len in 1...maxLen {
      first[len] = running
      running = (running + UInt32(bl[len])) << 1
    }

    var pairs: [(Int, Int)] = []
    for (s, L) in codeLengths.enumerated() where L > 0 {
      pairs.append((Int(L), s))
    }
    pairs.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }

    var nodes: [DecNode] = [DecNode()]
    @inline(__always) func newNode() -> Int {
      nodes.append(DecNode())
      return nodes.count - 1
    }

    var next = first
    for (len, sym) in pairs {
      let codeMSB = next[len]; next[len] &+= 1

      var v = codeMSB
      var rev: UInt32 = 0
      for _ in 0..<len {
        rev = (rev << 1) | (v & 1); v >>= 1
      }

      var idx = 0
      for i in 0..<len {
        if nodes[idx].sym != nil {
          throw HuffBuildError.invalidTree
        }
        let bit = (rev >> i) & 1
        if bit == 0 {
          if nodes[idx].left  == nil {
            nodes[idx].left = newNode()
          }
          idx = nodes[idx].left!
        } else {
          if nodes[idx].right == nil {
            nodes[idx].right = newNode()
          }
          idx = nodes[idx].right!
        }
      }
      if nodes[idx].left != nil || nodes[idx].right != nil {
        throw HuffBuildError.invalidTree
      }
      if nodes[idx].sym != nil {
        throw HuffBuildError.invalidTree
      }
      nodes[idx].sym = sym
    }

    return nodes
  }

  mutating func readToken(with tree: [DecNode]) throws -> Int {
    var idx = 0
    while tree[idx].sym == nil {
      if nBits == 0 {
        guard let byte = try reader.read() else {
          throw BitStreamError.unexpectedEOF
        }
        bits  = UInt32(byte)
        nBits = 8
      }
      let bit = bits & 1
      bits >>= 1; nBits &-= 1
      idx = (bit == 0) ? (tree[idx].left ?? -1) : (tree[idx].right ?? -1)
      if idx < 0 {
        throw VP8LError.invalidHuffmanTree
      }
    }
    return tree[idx].sym!
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
