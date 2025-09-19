public struct HuffmanCode {
  public var symbol: Int
  public var bits: UInt64
  public var depth: Int

  public init(symbol: Int = 0, bits: UInt64 = 0, depth: Int = 0) {
    self.symbol = symbol
    self.bits = bits
    self.depth = depth
  }
}

final class Node {
  var isBranch: Bool
  var weight: Int
  var symbol: Int
  var left: Node?
  var right: Node?

  init(
    isBranch: Bool = false,
    weight: Int,
    symbol: Int = 0,
    left: Node? = nil,
    right: Node? = nil)
  {
    self.isBranch = isBranch
    self.weight = weight
    self.symbol = symbol
    self.left = left
    self.right = right
  }
}

private struct NodeHeap {
  private(set) var a: [Node] = []

  var count: Int { a.count }
  var isEmpty: Bool { a.isEmpty }

  mutating func push(_ n: Node) {
    a.append(n)
    siftUp(from: a.count - 1)
  }

  mutating func pop() -> Node? {
    guard !a.isEmpty else {
      return nil
    }
    a.swapAt(0, a.count - 1)
    let out = a.removeLast()
    if !a.isEmpty {
      siftDown(from: 0)
    }
    return out
  }

  private mutating func siftUp(from i0: Int) {
    var i = i0
    while i > 0 {
      let p = (i - 1) >> 1
      if a[p].weight <= a[i].weight {
        break
      }
      a.swapAt(p, i)
      i = p
    }
  }

  private mutating func siftDown(from i0: Int) {
    var i = i0
    while true {
      let l = i * 2 + 1
      let r = l + 1
      var m = i
      if l < a.count && a[l].weight < a[m].weight {
        m = l
      }
      if r < a.count && a[r].weight < a[m].weight {
        m = r
      }
      if m == i {
        break
      }
      a.swapAt(i, m)
      i = m
    }
  }
}

func buildHuffmanTree(_ histo: [Int], maxDepth: Int) -> Node {
  let sum = histo.reduce(0, +)
  let minWeight = sum >> (maxDepth - 2)

  var heap = NodeHeap()

  for (symbol, weight) in histo.enumerated() where weight > 0 {
    heap.push(Node(weight: max(weight, minWeight), symbol: symbol))
  }

  if heap.count < 1 {
    heap.push(Node(weight: minWeight, symbol: 0))
  }

  while heap.count > 1 {
    let n1 = heap.pop()!
    let n2 = heap.pop()!
    heap.push(
      Node(
        isBranch: true,
        weight: n1.weight + n2.weight,
        left: n1,
        right: n2
      )
    )
  }

  return heap.pop()!
}

func buildHuffmanCodes(_ histo: [Int], maxDepth: Int) -> [HuffmanCode] {
  var codes = Array(repeating: HuffmanCode(), count: histo.count)

  let tree = buildHuffmanTree(histo, maxDepth: maxDepth)
  printHuffmanTree(tree)

  if !tree.isBranch {
    codes[tree.symbol] = HuffmanCode(symbol: tree.symbol, bits: 0, depth: -1)
    return codes
  }

  var symbols = [HuffmanCode]()
  setBitDepths(tree, &symbols, level: 0)

  symbols.sort {
    if $0.depth == $1.depth {
      return $0.symbol < $1.symbol
    }
    return $0.depth < $1.depth
  }

  var bits: UInt64 = 0
  var prevDepth = 0
  for s in symbols {
    let delta = s.depth - prevDepth
    if delta > 0 {
      bits <<= UInt64(delta)
    }
    codes[s.symbol].symbol = s.symbol
    codes[s.symbol].bits = bits
    codes[s.symbol].depth = s.depth
    bits += 1
    prevDepth = s.depth
  }

  dumpCanonicalTable(codes, maxRows: 512)

  return codes
}

func setBitDepths(_ node: Node?, _ out: inout [HuffmanCode], level: Int) {
  guard let node = node else {
    return
  }
  if !node.isBranch {
    out.append(HuffmanCode(symbol: node.symbol, bits: 0, depth: level))
    return
  }
  setBitDepths(node.left,  &out, level: level + 1)
  setBitDepths(node.right, &out, level: level + 1)
}

func writeHuffmanCodes(_ writer: inout BitWriter, _ codes: [HuffmanCode]) {
  var symbols = [Int](repeating: 0, count: 2)

  var count = 0
  for code in codes {
    if code.depth != 0 {
      if count < 2 {
        symbols[count] = code.symbol
      }
      count += 1
    }
    if count > 2 {
      break
    }
  }

  if count == 0 {
    writer.writeBits(1, 1)
    writer.writeBits(0, 3)
  } else if count <= 2 && symbols[0] < (1 << 8) && symbols[1] < (1 << 8) {
    writer.writeBits(1, 1)
    writer.writeBits(UInt64(count - 1), 1)
    if symbols[0] <= 1 {
      writer.writeBits(0, 1)
      writer.writeBits(UInt64(symbols[0]), 1)
    } else {
      writer.writeBits(1, 1)
      writer.writeBits(UInt64(symbols[0]), 8)
    }
    if count > 1 {
      writer.writeBits(UInt64(symbols[1]), 8)
    }
  } else {
    writeFullHuffmanCode(&writer, codes)
  }
}

func writeFullHuffmanCode(_ writer: inout BitWriter, _ codes: [HuffmanCode]) {
  var histo = Array(repeating: 0, count: 19)
  for code in codes {
    if (0...18).contains(code.depth) {
      histo[code.depth] += 1
    }
  }

  var count = 0
  for (i, c) in lengthCodeOrder.enumerated() {
    if histo[c] > 0 {
      count = max(i + 1, 4)
    }
  }

  writer.writeBits(0, 1)
  writer.writeBits(UInt64(count - 4), 4)

  let lengths = buildHuffmanCodes(histo, maxDepth: 7)
  for i in 0..<count {
//    let d = lengths[lengthCodeOrder[i]].depth
//    print("\(lengthCodeOrder[i]):\(d)", terminator: " ")
//    writer.writeBits(UInt64(d), 3)
    let sym = lengthCodeOrder[i]
    let d = (sym == 8) ? 1 : lengths[sym].depth
    print("\(sym):\(d)", terminator: " ")
    writer.writeBits(UInt64(d), 3)
  }

  writer.writeBits(0, 1)

  for code in codes {
    precondition((0..<lengths.count).contains(code.depth), "Depth out of range while writing length codes")
    writer.writeCode(lengths[code.depth])
  }
}
