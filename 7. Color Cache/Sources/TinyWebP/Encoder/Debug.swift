import Foundation
import CoreGraphics

func printHuffmanTree(
  _ root: Node?,
  showWeights: Bool = true,
  showSymbols: Bool = true,
  showNil: Bool = false
) {
  func label(_ n: Node) -> String {
    if n.isBranch {
      return showWeights ? "* w=\(n.weight)" : "*"
    } else {
      switch (showSymbols, showWeights) {
      case (true, true):
        return "s=\(n.symbol) w=\(n.weight)"
      case (true, false):
        return "s=\(n.symbol)"
      case (false, true):
        return "w=\(n.weight)"
      case (false, false):
        return "(leaf)"
      }
    }
  }

  var lines: [String] = []
  func walk(_ node: Node?, _ prefix: String, _ isTail: Bool, _ edge: String) {
    guard let node = node else {
      if showNil {
        lines.append(prefix + (isTail ? "`-- " : "|-- ") + edge + "(nil)")
      }
      return
    }
    let branch = isTail ? "`-- " : "|-- "
    let edgeTag = edge.isEmpty ? "" : "\(edge)"
    lines.append(prefix + branch + edgeTag + label(node))

    let nextPrefix = prefix + (isTail ? "    " : "|   ")
    let children: [(Node?, String)] = [(node.left, "L: "), (node.right, "R: ")]
    let lastIndex = children.indices.reversed().first { children[$0].0 != nil || showNil } ?? -1
    for (idx, (child, tag)) in children.enumerated() {
      let childIsTail = (idx == lastIndex)
      walk(child, nextPrefix, childIsTail, tag)
    }
  }

  if let r = root {
    lines.append(label(r))
    let children: [(Node?, String)] = [(r.left, "L: "), (r.right, "R: ")]
    let lastIndex = children.indices.reversed().first { children[$0].0 != nil || showNil } ?? -1
    for (idx, (child, tag)) in children.enumerated() {
      let isTail = (idx == lastIndex)
      walk(child, "", isTail, tag)
    }
  } else {
    lines.append("(empty)")
  }

  print(lines.joined(separator: "\n"))
}

func dumpCanonicalTable(_ codes: [HuffmanCode], maxRows: Int) {
  let rows = codes
    .filter { $0.depth > 0 }
    .sorted { ($0.depth, $0.symbol) < ($1.depth, $1.symbol) }
    .prefix(maxRows)
  for c in rows {
    print(String(format: "  %3d -> %@/%d", c.symbol, bitString(c.bits, len: c.depth), c.depth))
  }
  if rows.count < codes.filter({ $0.depth > 0 }).count {
    print("  ... (\(codes.filter{$0.depth>0}.count - rows.count) more)")
  }
}

func bitString(_ v: UInt64, len: Int) -> String {
  guard len > 0 else { return "" }
  var s = String(v, radix: 2)
  if s.count < len {
    s = String(repeating: "0", count: len - s.count) + s
  }
  return s
}

func debugDumpHistogramsGRBAD(
  _ histos: [[Int]],
  colorCacheBits: Int,
  topN: Int? = 32
) {
  precondition(histos.count >= 5, "histos must have 5 arrays (G,R,B,A,Dist)")

  let names = ["G","R","B","A","D"]
  for t in 0..<5 {
    let h = histos[t]
    let used = h.reduce(0) { $0 + ($1 > 0 ? 1 : 0) }
    let total = h.reduce(0, +)

    var pairs: [(Int, Int)] = []
    pairs.reserveCapacity(used)
    for (sym, cnt) in h.enumerated() where cnt > 0 { pairs.append((sym, cnt)) }
    pairs.sort { (a, b) in a.1 == b.1 ? a.0 < b.0 : a.1 > b.1 }
    let shown = topN.map { Array(pairs.prefix($0)) } ?? pairs

    print(String(format: "[%@] size=%d, used=%d, total=%d", names[t], h.count, used, total))

    if shown.isEmpty {
      print("  (none)")
    } else {
      var line = "  "
      for (i, p) in shown.enumerated() {
        let label = symbolLabel(treeIndex: t, sym: p.0, colorCacheBits: colorCacheBits)
        let chunk = "\(label):\(p.1)"
        if line.count + chunk.count + 2 > 100 {
          print(line)
          line = "  "
        }
        line += (i == 0 || line == "  ") ? chunk : ", " + chunk
      }
      if line != "  " { print(line) }
      if let topN, pairs.count > topN {
        print("  ... (\(pairs.count - topN) more)")
      }
    }
  }
}

private func symbolLabel(treeIndex: Int, sym: Int, colorCacheBits: Int) -> String {
  switch treeIndex {
  case 0:
    let ccSize = (colorCacheBits > 0) ? (1 << colorCacheBits) : 0
    if sym < 256 { return "G\(sym)" }
    else if sym < 256 + 24 { return "LEN\(sym - 256)" }
    else if sym < 256 + 24 + ccSize { return "CC\(sym - (256 + 24))" }
    else { return "Gx\(sym)" }
  case 1: return "R\(sym)"
  case 2: return "B\(sym)"
  case 3: return "A\(sym)"
  case 4: return "D\(sym)"
  default: return "\(sym)"
  }
}
